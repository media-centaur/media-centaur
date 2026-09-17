defmodule MediaCentaur.Acquisition.Jobs.RunPlan do
  @moduledoc """
  Oban worker that runs a draft plan's autonomous search-and-solve
  phase (media-search campaign Phase 3) as a **residual-driven
  search**, one scope at a time.

  One run walks the steps `Plans.SearchOrder` lays out for the want —
  the scopes whose pack could fit, widest first, then the rest as
  offers — but each step is searched **only for the units the previous
  steps' solve left uncovered** (the solver's residual — the wanted
  units no quality-floor group's solve assigned), and the run halts the
  moment the residual is empty. Wanting one episode of a finished
  season searches that episode's term and, when the single exists,
  nothing else; wanting most of a season starts at the season pack;
  wanting the show starts at the series term. A pack only ends the
  search for the units it *fits* (`Planner` fit gating), so a sparse
  want never grabs the whole series. Every search still goes through
  the corpus (`Corpus.search/2`, consult-first citizenship; `force:
  true` only on a user-initiated re-search), and a forced re-run also
  narrows lazily — it re-hammers only as deep as the residual requires.

  A unit the primary steps can't right-size — nothing but an over-broad
  pack covers it — lands `unfound` carrying the best pack the fallback
  steps found as an *offer* (the pack the user can opt into, over-grab
  spelled out on the board), never an auto-grab.

  Results are identity-verified (`TitleMatcher.coverage/2`), plan-wide
  exclusions filtered, and `Planner.solve/3` assigns candidates by the
  settled objective hierarchy. Assignments land on the plan units
  (found / unfound) and the plan transitions to `ready` for the user's
  steering pass.

  Movie plans have no scopes to walk. Their terms are alternate
  phrasings of one want rather than a narrowing sequence, so **every**
  term is searched and the pick is the best of the union, ordered by
  `Search.ReleasePreference` (`TitleMatcher.matches?/2` identity). When
  nothing acceptable exists but identity-verified releases do, the unit
  lands unfound carrying `below_floor_count` — the "lower quality
  available" verdict the board turns into an offer instead of a bare
  gap (campaign `below-floor-releases`).

  Broadcasts `PlanEvents.SearchActivity` per term (the live activity
  feed), `PlanEvents.SearchProgress` per step (the board's expectation
  panel), and `PlanEvents.Changed` when the rows move. Failures mark
  the plan's `error` and still transition to `ready` — a reported gap,
  not a stuck spinner.
  """

  use Oban.Worker, queue: :acquisition, unique: [period: 60, keys: [:plan_id]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{
    AutoGrabSettings,
    Corpus,
    Cours,
    CoverageGuard,
    PlanEvents,
    Planner,
    Plans
  }

  alias MediaCentaur.Acquisition.Plans.{MatchCriteria, Plan, PlanUnit, SearchOrder}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{CourCoverage, CourQueries, Quality, ReleaseCoverage}
  alias MediaCentaur.Search.{ReleasePreference, ReleaseRedFlags, TitleMatcher}
  alias MediaCentaur.Topics

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"plan_id" => plan_id} = args}) do
    force? = Map.get(args, "force", false)

    case Plans.fetch(plan_id) do
      {:ok, %Plan{status: "planning"} = plan} ->
        run(plan, force?)

      {:ok, %Plan{}} ->
        {:ok, :not_planning}

      {:error, :not_found} ->
        {:ok, :not_found}
    end
  end

  defp run(plan, force?) do
    units = plan.id |> Plans.units_for() |> Enum.reject(&(&1.status == "excluded"))

    case plan.tmdb_type do
      "tv" -> run_tv(plan, units, force?)
      "movie" -> run_movie(plan, units, force?)
    end

    case Repo.update(Plan.transition_changeset(Repo.reload!(plan), "ready", ["planning"])) do
      {:ok, ready} ->
        Plans.broadcast_changed(ready)
        Log.info(:acquisition, "plan ready — #{plan.title}")
        :ok

      {:error, _changeset} ->
        # The plan left `planning` while we were running it — almost always a
        # concurrent discard (user walked away). That is a normal race, not a
        # fault: the plan is already in its terminal state, so finish quietly
        # rather than crashing the job (which would mint a spurious `plan run
        # crashed` error incident for an ordinary cancellation).
        Log.info(
          :acquisition,
          "plan left planning mid-run — skipping ready transition — #{plan.title}"
        )

        :ok
    end
  rescue
    exception ->
      # The moduledoc contract — a reported gap, never a stuck spinner —
      # must hold for unexpected raises too, not just handled search
      # errors: an Oban crash loop retries the same deterministic
      # failure while the plan sits in `planning` forever.
      Log.error(
        :acquisition,
        "plan run crashed — #{plan.title} — #{Exception.message(exception)}"
      )

      case Repo.update(
             Plan.failed_changeset(
               Repo.reload!(plan),
               "planning crashed: #{Exception.message(exception)}"
             )
           ) do
        {:ok, failed} -> Plans.broadcast_changed(failed)
        {:error, _already_left_planning} -> :ok
      end

      {:error, exception}
  end

  # ---------------------------------------------------------------------------
  # TV — the search steps + planner
  # ---------------------------------------------------------------------------

  defp run_tv(plan, units, force?) do
    wanted = Enum.map(units, &{&1.season_number, &1.episode_number})
    # `{unit, air_date}` pairs drive the cour-aware coverage guard: a
    # candidate is capped to the units it could physically contain (aired
    # on or before its publish date).
    unit_air_dates = Enum.map(units, &{{&1.season_number, &1.episode_number}, &1.air_date})
    excluded = units |> Enum.flat_map(& &1.excluded_release_guids) |> MapSet.new()
    identity = series_criteria(plan)
    # `all_wanted` is the whole plan's want, used as the fit numerator so
    # a season's density reads the same across quality-floor groups.
    plan_prefs = Map.put(prefs(plan), :all_wanted, wanted)

    search_context = %{
      identity: identity,
      excluded: excluded,
      unit_air_dates: unit_air_dates,
      force?: force?
    }

    # One solve per quality-floor group: a unit's own `min_quality` is
    # the title's lower-quality acceptance (ADR-063 §2); nothing else
    # sets one. Grouping keeps the planner blind to where a floor came
    # from.
    floor_groups =
      units
      |> Enum.group_by(&(&1.min_quality || plan_prefs.min_quality))
      |> Map.new(fn {floor, group_units} ->
        {floor, Enum.map(group_units, &{&1.season_number, &1.episode_number})}
      end)

    # `steps` (walked, done) and `passed` (reached with nothing to
    # search for the residual) together say which of the order's steps
    # the run has been through; the rest report as skipped at the end.
    initial = %{
      options: [],
      terms_by_guid: %{},
      assignment_by_unit: %{},
      offers_by_unit: %{},
      below_floor_by_unit: %{},
      halted?: false,
      residual: wanted,
      steps: [],
      passed: []
    }

    order = SearchOrder.steps(plan, wanted, plan_prefs)

    state =
      Enum.reduce_while(order, initial, fn step, state ->
        case step.terms.(state.residual) do
          [] ->
            {:cont, %{state | passed: [{step.scope, step.kind} | state.passed]}}

          terms ->
            active = %{
              scope: step.scope,
              kind: step.kind,
              state: :active,
              term_count: length(terms),
              residual_after: nil
            }

            broadcast_progress(plan, length(wanted), order, state, active)

            state = gather_step(state, plan, terms, search_context)

            if state.halted? do
              {:halt, state}
            else
              state = solve_groups(state, wanted, floor_groups, plan_prefs)
              done = %{active | state: :done, residual_after: length(state.residual)}
              state = %{state | steps: state.steps ++ [done]}

              if state.residual == [], do: {:halt, state}, else: {:cont, state}
            end
        end
      end)

    # A halted run belongs to a plan the user already discarded — no
    # solve, no persistence, no further broadcasts (ADR-063 §3).
    if state.halted? do
      :ok
    else
      skipped =
        for step <- order,
            not been_through?(state, step),
            do: %{
              scope: step.scope,
              kind: step.kind,
              state: :skipped,
              term_count: nil,
              residual_after: nil
            }

      broadcast_progress(plan, length(wanted), order, %{state | steps: state.steps ++ skipped}, nil)

      state = add_cour_offers(state, plan, wanted, excluded, force?, plan_prefs)

      Enum.each(units, fn unit ->
        key = {unit.season_number, unit.episode_number}

        case Map.get(state.assignment_by_unit, key) do
          nil ->
            offer = offer_attrs(Map.get(state.offers_by_unit, key))
            below_floor_count = Map.get(state.below_floor_by_unit, key, 0)
            {:ok, _} = Repo.update(PlanUnit.unfound_changeset(unit, offer, below_floor_count))

          assignment ->
            {:ok, _} =
              Repo.update(
                PlanUnit.assign_changeset(unit, assignment_attrs(assignment, state.terms_by_guid))
              )
        end
      end)
    end
  end

  defp been_through?(state, step) do
    key = {step.scope, step.kind}
    key in state.passed or Enum.any?(state.steps, &({&1.scope, &1.kind} == key))
  end

  # One step's searches folded into the cumulative option pool. Every
  # term goes through the corpus; identity is verified per result;
  # plan-wide exclusions are dropped before solving (a release the user
  # rejected for one episode is almost never what they want for
  # another); guid dedup keeps the first term that surfaced a release.
  defp gather_step(state, plan, terms, search_context) do
    Enum.reduce_while(terms, state, fn term, state ->
      if still_planning?(plan) do
        {:cont, gather_term(state, plan, term, search_context)}
      else
        {:halt, %{state | halted?: true}}
      end
    end)
  end

  defp gather_term(state, plan, term, %{
         identity: identity,
         excluded: excluded,
         unit_air_dates: unit_air_dates,
         force?: force?
       }) do
    plan
    |> search(term, force?)
    |> Enum.reduce(state, fn result, state ->
      with false <- ReleaseRedFlags.suspicious?(result.title, result.size_bytes),
           false <- MapSet.member?(excluded, result.guid),
           false <- Map.has_key?(state.terms_by_guid, result.guid),
           {:ok, scope} <- TitleMatcher.coverage(result, identity) do
        option = %Planner.Option{
          result: result,
          scope: scope,
          coverable: CoverageGuard.coverable_units(unit_air_dates, result.publish_date)
        }

        %{
          state
          | options: [option | state.options],
            terms_by_guid: Map.put(state.terms_by_guid, result.guid, term)
        }
      else
        _ -> state
      end
    end)
  end

  # Re-solves every floor group over the cumulative pool and recomputes
  # the residual. Rebuilt from scratch each step — the planner is pure
  # and cheap, and a later step's options only ever improve coverage.
  defp solve_groups(state, wanted, floor_groups, plan_prefs) do
    options = Enum.reverse(state.options)

    {assignment_by_unit, offers_by_unit, below_floor_by_unit} =
      Enum.reduce(floor_groups, {%{}, %{}, %{}}, fn {group_min, group_wanted},
                                                    {assigns, offers, below} ->
        solution = Planner.solve(group_wanted, options, %{plan_prefs | min_quality: group_min})

        assigns =
          for assignment <- solution.assignments,
              unit <- assignment.units,
              into: assigns,
              do: {unit, assignment}

        {assigns, Map.merge(offers, solution.offers), Map.merge(below, solution.below_floor)}
      end)

    %{
      state
      | assignment_by_unit: assignment_by_unit,
        offers_by_unit: offers_by_unit,
        below_floor_by_unit: below_floor_by_unit,
        residual: Enum.reject(wanted, &Map.has_key?(assignment_by_unit, &1))
    }
  end

  # Cour-aware surfacing (Phase 2). For units the search left unfound
  # *because* the coverage guard trimmed an otherwise-covering pack (the
  # later-cour signal), fetch the season, confirm the unit is in a later
  # broadcast run, search run-shaped queries, and attach any matching
  # pack as an **offer** — never an auto-grab (later-cour naming is fuzzy;
  # the user confirms on the board). The trim signal gates the TMDB fetch
  # so a plain dry show never pays for it.
  defp add_cour_offers(state, plan, wanted, excluded, force?, plan_prefs) do
    unfound = Enum.reject(wanted, &Map.has_key?(state.assignment_by_unit, &1))

    case later_run_units(plan, trimmed_units(state.options, unfound)) do
      [] ->
        state

      later ->
        options = cour_options(plan, later, excluded, force?)
        solution = Planner.solve(Enum.map(later, &elem(&1, 0)), options, plan_prefs)
        %{state | offers_by_unit: Map.merge(state.offers_by_unit, solution.offers)}
    end
  end

  # Unfound units that some gathered option's *scope* covers but its
  # `coverable` cap trimmed — i.e. a pack that should hold them but
  # physically cannot (it predates their air date). That is the later-cour
  # tell, and the only case worth a season fetch.
  defp trimmed_units(options, unfound) do
    Enum.filter(unfound, fn {season, episode} ->
      Enum.any?(options, fn option ->
        ReleaseCoverage.covers?(option.scope, season, episode) and
          option.coverable != :all and
          not MapSet.member?(option.coverable, {season, episode})
      end)
    end)
  end

  # Pairs each candidate unit with the later run it belongs to (one season
  # fetch per distinct season; units not in a later run are dropped).
  defp later_run_units(_plan, []), do: []

  defp later_run_units(plan, candidates) do
    candidates
    |> Enum.group_by(fn {season, _episode} -> season end)
    |> Enum.flat_map(fn {season, units} ->
      runs = Cours.runs_for_season(plan.tmdb_id, season)
      Enum.map(units, fn unit -> {unit, Cours.later_run(runs, unit)} end)
    end)
    |> Enum.reject(fn {_unit, run} -> is_nil(run) end)
  end

  # Searches the run-shaped queries for each distinct later run and
  # classifies results against that run (`CourCoverage`). Matches become
  # offer-only options so the planner only ever surfaces them as offers.
  defp cour_options(plan, later, excluded, force?) do
    later
    |> Enum.map(fn {_unit, run} -> run end)
    |> Enum.uniq_by(& &1.index)
    |> Enum.flat_map(fn run ->
      plan.title
      |> CourQueries.build(run)
      |> Enum.flat_map(fn {term, _opts} ->
        plan
        |> search(term, force?)
        |> Enum.flat_map(&cour_option(&1, plan, run, excluded))
      end)
    end)
    |> Enum.uniq_by(& &1.result.guid)
  end

  defp cour_option(result, plan, run, excluded) do
    with false <- ReleaseRedFlags.suspicious?(result.title, result.size_bytes),
         false <- MapSet.member?(excluded, result.guid),
         scope when scope != :no_match <- CourCoverage.classify(result.title, plan.title, run) do
      [%Planner.Option{result: result, scope: scope, offer_only: true}]
    else
      _ -> []
    end
  end

  defp series_criteria(plan), do: MatchCriteria.from(plan)

  defp assignment_attrs(assignment, terms_by_guid) do
    %{
      assigned_guid: assignment.result.guid,
      assigned_title: assignment.result.title,
      assigned_term: Map.get(terms_by_guid, assignment.result.guid),
      assigned_quality: Quality.display_label(assignment.result.title),
      assigned_seeders: assignment.result.seeders,
      assigned_indexer_id: assignment.result.indexer_id,
      assigned_size_bytes: assignment.result.size_bytes,
      assigned_scope: ReleaseCoverage.scope_label(assignment.scope)
    }
  end

  defp offer_attrs(nil), do: nil

  defp offer_attrs(%Planner.Option{result: result, scope: scope}) do
    %{
      offered_guid: result.guid,
      offered_title: result.title,
      offered_scope: ReleaseCoverage.scope_label(scope),
      offered_size_bytes: result.size_bytes
    }
  end

  # ---------------------------------------------------------------------------
  # Movies — precise-to-broad terms, best acceptable pick
  # ---------------------------------------------------------------------------

  defp run_movie(plan, units, force?) do
    excluded = units |> Enum.flat_map(& &1.excluded_release_guids) |> MapSet.new()

    criteria = MatchCriteria.from(plan)
    plan_prefs = prefs(plan)

    # A movie plan has one unit; its floor override (the title's
    # lower-quality acceptance) wins over the plan criteria when present.
    min_quality =
      case units do
        [%PlanUnit{min_quality: floor} | _] when is_binary(floor) -> floor
        _ -> plan_prefs.min_quality
      end

    movie_context = %{
      criteria: criteria,
      excluded: excluded,
      min_quality: min_quality,
      plan_prefs: plan_prefs,
      force?: force?
    }

    # Unlike the TV search, the movie terms are **alternate phrasings of
    # one want**, not a narrowing sequence: there is a single unit, so
    # "covered" happens on the first hit and stopping there would let
    # whichever term the year happened to match decide the quality
    # ceiling. Release groups tag a film with whichever year their source
    # used, so the year term routinely matches a handful of releases while
    # every better copy sits behind the year-less one. Every term is
    # therefore searched and the pick is the best of the union — the only
    # early exit is the user discarding the plan.
    #
    # Alongside the pick, every term accumulates the identity-verified
    # releases *below* the floor (by guid — terms overlap): when nothing
    # acceptable exists, that count is the "lower quality available"
    # verdict the unit carries instead of a bare unfound.
    {best, below_floor_guids} =
      plan
      |> SearchOrder.terms([], %{})
      |> Enum.reduce_while({nil, MapSet.new()}, fn term, acc ->
        if still_planning?(plan) do
          {:cont, movie_term_step(plan, term, acc, movie_context)}
        else
          {:halt, acc}
        end
      end)

    if still_planning?(plan) do
      persist_movie_outcome(units, best, below_floor_guids)
    else
      :ok
    end
  end

  # Folds one term's results into the running {best, below_floor_guids}.
  # `ReleasePreference.better_of/3` keeps the incumbent on an exact tie,
  # so walking the terms precise-before-broad makes the year-matched
  # candidate win ties against an equal one from the bare title — the
  # likelier identity, for free, with no extra tiebreak component.
  defp movie_term_step(plan, term, {best, below_floor_guids}, %{
         criteria: criteria,
         excluded: excluded,
         min_quality: min_quality,
         plan_prefs: plan_prefs,
         force?: force?
       }) do
    matched =
      plan
      |> search(term, force?)
      |> Enum.filter(fn result ->
        not ReleaseRedFlags.suspicious?(result.title, result.size_bytes) and
          not MapSet.member?(excluded, result.guid) and
          TitleMatcher.matches?(result, criteria)
      end)

    pick =
      matched
      |> Enum.filter(&Quality.acceptable?(&1.quality, min_quality, plan_prefs.max_quality))
      |> ReleasePreference.best(plan_prefs.size_preference)

    below_floor_guids =
      matched
      |> Enum.filter(&(Quality.rank(&1.quality) < Quality.label_rank(min_quality)))
      |> MapSet.new(& &1.guid)
      |> MapSet.union(below_floor_guids)

    {best_of_terms(best, pick, term, plan_prefs.size_preference), below_floor_guids}
  end

  defp best_of_terms(best, nil, _term, _size_preference), do: best
  defp best_of_terms(nil, pick, term, _size_preference), do: {pick, term}

  defp best_of_terms({incumbent, incumbent_term}, pick, term, size_preference) do
    case ReleasePreference.better_of(incumbent, pick, size_preference) do
      ^incumbent -> {incumbent, incumbent_term}
      winner -> {winner, term}
    end
  end

  defp persist_movie_outcome(units, best, below_floor_guids) do
    Enum.each(units, fn unit ->
      case best do
        nil ->
          {:ok, _} =
            Repo.update(PlanUnit.unfound_changeset(unit, nil, MapSet.size(below_floor_guids)))

        {result, term} ->
          {:ok, _} =
            Repo.update(
              PlanUnit.assign_changeset(unit, %{
                assigned_guid: result.guid,
                assigned_title: result.title,
                assigned_term: term,
                assigned_quality: Quality.display_label(result.title),
                assigned_seeders: result.seeders,
                assigned_indexer_id: result.indexer_id,
                assigned_size_bytes: result.size_bytes,
                assigned_scope: nil
              })
            )
      end
    end)
  end

  # ---------------------------------------------------------------------------

  defp search(plan, term, force?) do
    opts = SearchOrder.search_opts(plan)
    served_from = if not force? and Corpus.fresh?(term, opts), do: :corpus, else: :live
    outcome = Corpus.search(term, Keyword.put(opts, :force, force?))

    activity =
      case outcome do
        {:ok, results} ->
          %PlanEvents.SearchActivity{
            plan_id: plan.id,
            term: term,
            outcome: served_from,
            result_count: length(results)
          }

        {:error, _reason} ->
          %PlanEvents.SearchActivity{plan_id: plan.id, term: term, outcome: :error}
      end

    Topics.publish(Topics.acquisition_updates(), activity)

    case outcome do
      {:ok, results} ->
        results

      {:error, reason} ->
        # The plan's own `error` field (set just below, shown on the board) is
        # the canonical surface for a failed search — usually a transient indexer
        # timeout that retries next cycle. The parallel `Log.warning` would mint a
        # duplicate `:log` incident, so skip it; the plan board is where this
        # belongs.
        Log.warning(:acquisition, "plan search failed — #{term} — #{inspect(reason)}",
          mc_incident: :skip
        )

        {:ok, _} = Repo.update(Plan.error_changeset(Repo.reload!(plan), "search failed: #{term}"))
        []
    end
  end

  # Full itinerary snapshot: steps already walked (done/skipped), the
  # active step if any, then the order's untouched steps as pending. A
  # step passed with nothing to search never appears.
  defp broadcast_progress(plan, wanted_count, order, state, active) do
    taken =
      Enum.map(state.steps, &{&1.scope, &1.kind}) ++
        state.passed ++ if active, do: [{active.scope, active.kind}], else: []

    pending =
      for step <- order,
          {step.scope, step.kind} not in taken,
          do: %{
            scope: step.scope,
            kind: step.kind,
            state: :pending,
            term_count: nil,
            residual_after: nil
          }

    progress = %PlanEvents.SearchProgress{
      plan_id: plan.id,
      wanted: wanted_count,
      steps: state.steps ++ List.wrap(active) ++ pending
    }

    Topics.publish(Topics.acquisition_updates(), progress)
  end

  # Quality bounds from the plan's criteria; the fit inputs (span sizes
  # and threshold) the one way every reader must build them
  # (`SearchOrder.fit_prefs/2`), so the gate and the order agree.
  defp prefs(plan) do
    settings = AutoGrabSettings.load()
    criteria = plan.criteria || %{}

    Map.merge(
      %{
        min_quality: Map.get(criteria, "min_quality") || AutoGrabSettings.floor(),
        max_quality: Map.get(criteria, "max_quality") || settings.default_max_quality,
        size_preference: settings.size_preference
      },
      SearchOrder.fit_prefs(plan, settings)
    )
  end

  # ADR-063 §3: plan status is the cancellation channel — the run
  # re-checks it between search terms so a Stop lands within one
  # search, never at the end of the run.
  defp still_planning?(plan) do
    match?(%Plan{status: "planning"}, Repo.reload(plan))
  end
end
