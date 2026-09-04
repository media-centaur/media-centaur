defmodule MediaCentaur.Acquisition.Jobs.RunPlan do
  @moduledoc """
  Oban worker that runs a draft plan's autonomous search-and-solve
  phase (media-search campaign Phase 3) as a **residual-driven
  descent** of the coverage ladder.

  One run walks the rungs broad-to-narrow — series term, per-season
  terms, per-unit episode terms — but each rung is searched **only for
  the units the previous rungs' solve left uncovered** (the solver's
  residual — the wanted units no quality-floor group's solve
  assigned). A pack only ends the descent for the units it *fits*
  (`Planner` fit gating): wanting most of a season takes the season
  pack and stops there, but wanting a sparse slice leaves those units
  in the residual so the descent keeps going to the right-sized
  episode terms — picking one episode never grabs the whole series.
  Every search still goes through the corpus (`Corpus.search/2`,
  consult-first citizenship; `force: true` only on a user-initiated
  re-search), and a forced re-run also descends lazily — it re-hammers
  only as deep as the residual requires.

  A unit the descent can't right-size — nothing but an over-broad pack
  covers it — lands `unfound` carrying that pack as an *offer* (the
  pack the user can opt into, over-grab spelled out on the board),
  never an auto-grab.

  Results are identity-verified (`TitleMatcher.coverage/2`), plan-wide
  exclusions filtered, and `Planner.solve/3` assigns candidates by the
  settled objective hierarchy. Assignments land on the plan units
  (found / unfound) and the plan transitions to `ready` for the user's
  steering pass.

  Movie plans skip the ladder: one term, best acceptable result by
  quality-then-seeders (`TitleMatcher.matches?/2` identity). When
  nothing acceptable exists but identity-verified releases do, the unit
  lands unfound carrying `below_floor_count` — the "lower quality
  available" verdict the board turns into an offer instead of a bare
  gap (campaign `below-floor-releases`).

  Broadcasts `PlanEvents.SearchActivity` per term (the live activity
  feed), `PlanEvents.DescentStatus` per rung (the board's expectation
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

  alias MediaCentaur.Acquisition.Plans.{LadderTerms, Plan, PlanUnit}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{CourCoverage, CourQueries, Criteria, Quality, ReleaseCoverage}
  alias MediaCentaur.Search.{ReleaseRedFlags, TitleMatcher}
  alias MediaCentaur.Topics

  @rung_ids [:series, :seasons, :episodes]

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
  # TV — the coverage ladder + planner
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

    # One solve per quality-floor group (ADR-056 Q4): a unit inside its
    # patience window carries an elevated `min_quality`, fails its
    # group's acceptability, and stays in the residual — so the descent
    # continues for it alone. The planner stays time-blind.
    floor_groups =
      units
      |> Enum.group_by(&(&1.min_quality || plan_prefs.min_quality))
      |> Map.new(fn {floor, group_units} ->
        {floor, Enum.map(group_units, &{&1.season_number, &1.episode_number})}
      end)

    initial = %{
      options: [],
      terms_by_guid: %{},
      assignment_by_unit: %{},
      offers_by_unit: %{},
      below_floor_by_unit: %{},
      halted?: false,
      residual: wanted,
      stages: []
    }

    state =
      Enum.reduce_while(rungs(plan), initial, fn {rung_id, terms_for}, state ->
        terms = terms_for.(state.residual)
        active = %{id: rung_id, state: :active, term_count: length(terms), residual_after: nil}
        broadcast_descent(plan, length(wanted), state.stages, active)

        state = gather_rung(state, plan, terms, search_context)

        if state.halted? do
          {:halt, state}
        else
          state = solve_groups(state, wanted, floor_groups, plan_prefs)
          done = %{active | state: :done, residual_after: length(state.residual)}
          state = %{state | stages: state.stages ++ [done]}

          if state.residual == [], do: {:halt, state}, else: {:cont, state}
        end
      end)

    # A halted run belongs to a plan the user already discarded — no
    # solve, no persistence, no further broadcasts (ADR-063 §3).
    if state.halted? do
      :ok
    else
      skipped =
        for {rung_id, _terms_for} <- rungs(plan),
            not Enum.any?(state.stages, &(&1.id == rung_id)),
            do: %{id: rung_id, state: :skipped, term_count: nil, residual_after: nil}

      broadcast_descent(plan, length(wanted), state.stages ++ skipped, nil)

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

  # The coverage ladder, broad to narrow. Each rung sees the current
  # residual — the wanted units no acceptable option covers yet — and
  # emits only the terms that residual justifies. The descent never
  # searches below a span the solver already covered.
  defp rungs(plan) do
    [
      {:series, fn _residual -> LadderTerms.series_terms(plan) end},
      {:seasons,
       fn residual ->
         seasons = residual |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
         LadderTerms.season_terms(plan, seasons)
       end},
      {:episodes, fn residual -> LadderTerms.episode_terms(plan, residual) end}
    ]
  end

  # One rung's searches folded into the cumulative option pool. Every
  # term goes through the corpus; identity is verified per result;
  # plan-wide exclusions are dropped before solving (a release the user
  # rejected for one episode is almost never what they want for
  # another); guid dedup keeps the first term that surfaced a release.
  defp gather_rung(state, plan, terms, search_context) do
    Enum.reduce_while(terms, state, fn {term, opts}, state ->
      if still_planning?(plan) do
        {:cont, gather_term(state, plan, {term, opts}, search_context)}
      else
        {:halt, %{state | halted?: true}}
      end
    end)
  end

  defp gather_term(state, plan, {term, opts}, %{
         identity: identity,
         excluded: excluded,
         unit_air_dates: unit_air_dates,
         force?: force?
       }) do
    plan
    |> search(term, opts, force?)
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
  # the residual. Rebuilt from scratch each rung — the planner is pure
  # and cheap, and a later rung's options only ever improve coverage.
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

  # Cour-aware surfacing (Phase 2). For units the descent left unfound
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
      |> Enum.flat_map(fn {term, opts} ->
        plan
        |> search(term, opts, force?)
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

  defp series_criteria(plan) do
    %Criteria{
      type: :tmdb,
      title: plan.title,
      tmdb_type: :tv,
      season_number: nil,
      episode_number: nil,
      origin_country: plan.origin_country || []
    }
  end

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

    criteria = %Criteria{type: :tmdb, title: plan.title, tmdb_type: :movie, year: plan.year}
    plan_prefs = prefs(plan)

    # A movie plan has one unit; its floor override (patience
    # elevation) wins over the plan criteria when present.
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

    # Same residual discipline as the TV ladder: the broader (year-less)
    # term is searched only when the year term yields nothing acceptable.
    # Alongside the pick, every walked rung accumulates the identity-
    # verified releases *below* the floor (by guid — rungs overlap): when
    # nothing acceptable exists, that count is the "lower quality
    # available" verdict the unit carries instead of a bare unfound.
    {best, below_floor_guids} =
      plan
      |> LadderTerms.for_plan([])
      |> Enum.reduce_while({nil, MapSet.new()}, fn {term, opts}, {_best, below_floor_guids} = acc ->
        if still_planning?(plan) do
          movie_term_step(plan, {term, opts}, below_floor_guids, movie_context)
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

  defp movie_term_step(plan, {term, opts}, below_floor_guids, %{
         criteria: criteria,
         excluded: excluded,
         min_quality: min_quality,
         plan_prefs: plan_prefs,
         force?: force?
       }) do
    matched =
      plan
      |> search(term, opts, force?)
      |> Enum.filter(fn result ->
        not ReleaseRedFlags.suspicious?(result.title, result.size_bytes) and
          not MapSet.member?(excluded, result.guid) and
          TitleMatcher.matches?(result, criteria)
      end)

    pick =
      matched
      |> Enum.filter(&Quality.acceptable?(&1.quality, min_quality, plan_prefs.max_quality))
      |> Enum.max_by(
        &{Quality.rank(&1.quality),
         Quality.source_rank(Quality.source(&1.title), plan_prefs.size_preference), &1.seeders || 0},
        fn -> nil end
      )

    below_floor_guids =
      matched
      |> Enum.filter(&(Quality.rank(&1.quality) < Quality.label_rank(min_quality)))
      |> MapSet.new(& &1.guid)
      |> MapSet.union(below_floor_guids)

    case pick do
      nil -> {:cont, {nil, below_floor_guids}}
      result -> {:halt, {{result, term}, below_floor_guids}}
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

  defp search(plan, term, opts, force?) do
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

  # Full itinerary snapshot: stages already walked (done/skipped), the
  # active rung if any, then the untouched rungs as pending.
  defp broadcast_descent(plan, wanted_count, walked_stages, active) do
    taken = Enum.map(walked_stages, & &1.id) ++ if active, do: [active.id], else: []

    pending =
      for rung_id <- @rung_ids,
          rung_id not in taken,
          do: %{id: rung_id, state: :pending, term_count: nil, residual_after: nil}

    status = %PlanEvents.DescentStatus{
      plan_id: plan.id,
      wanted: wanted_count,
      stages: walked_stages ++ List.wrap(active) ++ pending
    }

    Topics.publish(Topics.acquisition_updates(), status)
  end

  defp prefs(plan) do
    settings = AutoGrabSettings.load()
    criteria = plan.criteria || %{}
    span_sizes = plan.span_sizes || %{}

    %{
      min_quality: Map.get(criteria, "min_quality") || settings.default_min_quality,
      max_quality: Map.get(criteria, "max_quality") || settings.default_max_quality,
      size_preference: settings.size_preference,
      span_sizes: span_sizes,
      # Fit-gating is media-search's lever: only plans that captured the
      # span sizes (TV selections) opt in. Movies and tracking drops have
      # none → `nil` → the planner stays broad-first. Percent → fraction.
      pack_min_fit: if(span_sizes != %{}, do: settings.pack_min_fit / 100)
    }
  end

  # ADR-063 §3: plan status is the cancellation channel — the run
  # re-checks it between search terms so a Stop lands within one
  # search, never at the end of the ladder.
  defp still_planning?(plan) do
    match?(%Plan{status: "planning"}, Repo.reload(plan))
  end
end
