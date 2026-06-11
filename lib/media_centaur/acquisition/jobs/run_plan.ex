defmodule MediaCentaur.Acquisition.Jobs.RunPlan do
  @moduledoc """
  Oban worker that runs a draft plan's autonomous search-and-solve
  phase (media-search campaign Phase 3) as a **residual-driven
  descent** of the coverage ladder.

  One run walks the rungs broad-to-narrow — series term, per-season
  terms, per-unit episode terms — but each rung is searched **only for
  the units the previous rungs' solve left uncovered** (the solver's
  residual — the wanted units no quality-floor group's solve
  assigned). An acceptable complete-series pack ends the run after one
  search; season packs end it before any episode term fires; only
  proven gaps pay for episode searches. Every search still goes
  through the corpus (`Corpus.search/2`, consult-first citizenship;
  `force: true` only on a user-initiated re-search), and a forced
  re-run also descends lazily — it re-hammers only as deep as the
  residual requires.

  Results are identity-verified (`TitleMatcher.coverage/2`), plan-wide
  exclusions filtered, and `Planner.solve/3` assigns candidates by the
  settled objective hierarchy. Assignments land on the plan units
  (found / unfound) and the plan transitions to `ready` for the user's
  steering pass.

  Movie plans skip the ladder: one term, best acceptable result by
  quality-then-seeders (`TitleMatcher.matches?/2` identity).

  Broadcasts `PlanEvents.SearchActivity` per term (the live activity
  feed), `PlanEvents.DescentStatus` per rung (the board's expectation
  panel), and `PlanEvents.Changed` when the rows move. Failures mark
  the plan's `error` and still transition to `ready` — a reported gap,
  not a stuck spinner.
  """

  use Oban.Worker, queue: :acquisition, unique: [period: 60, keys: [:plan_id]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{AutoGrabSettings, Corpus, PlanEvents, Planner, Plans}
  alias MediaCentaur.Acquisition.Plans.{LadderTerms, Plan, PlanUnit}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{Criteria, Quality, ReleaseRedFlags, TitleMatcher}
  alias MediaCentaur.Topics

  @rung_ids [:series, :seasons, :episodes]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"plan_id" => plan_id} = args}) do
    force? = Map.get(args, "force", false)

    case Plans.get(plan_id) do
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

    {:ok, ready} =
      Repo.update(Plan.transition_changeset(Repo.reload!(plan), "ready", ["planning"]))

    Plans.broadcast_changed(ready)
    Log.info(:acquisition, "plan ready — #{plan.title}")
    :ok
  end

  # ---------------------------------------------------------------------------
  # TV — the coverage ladder + planner
  # ---------------------------------------------------------------------------

  defp run_tv(plan, units, force?) do
    wanted = Enum.map(units, &{&1.season_number, &1.episode_number})
    excluded = units |> Enum.flat_map(& &1.excluded_release_guids) |> MapSet.new()
    identity = series_criteria(plan)
    plan_prefs = prefs(plan)

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
      residual: wanted,
      stages: []
    }

    state =
      Enum.reduce_while(rungs(plan), initial, fn {rung_id, terms_for}, state ->
        terms = terms_for.(state.residual)
        active = %{id: rung_id, state: :active, term_count: length(terms), residual_after: nil}
        broadcast_descent(plan, length(wanted), state.stages, active)

        state =
          state
          |> gather_rung(plan, terms, identity, excluded, force?)
          |> solve_groups(wanted, floor_groups, plan_prefs)

        done = %{active | state: :done, residual_after: length(state.residual)}
        state = %{state | stages: state.stages ++ [done]}

        if state.residual == [], do: {:halt, state}, else: {:cont, state}
      end)

    skipped =
      for {rung_id, _terms_for} <- rungs(plan),
          not Enum.any?(state.stages, &(&1.id == rung_id)),
          do: %{id: rung_id, state: :skipped, term_count: nil, residual_after: nil}

    broadcast_descent(plan, length(wanted), state.stages ++ skipped, nil)

    Enum.each(units, fn unit ->
      key = {unit.season_number, unit.episode_number}

      case Map.get(state.assignment_by_unit, key) do
        nil ->
          {:ok, _} = Repo.update(PlanUnit.unfound_changeset(unit))

        assignment ->
          {:ok, _} =
            Repo.update(
              PlanUnit.assign_changeset(unit, assignment_attrs(assignment, state.terms_by_guid))
            )
      end
    end)
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
  defp gather_rung(state, plan, terms, identity, excluded, force?) do
    Enum.reduce(terms, state, fn {term, opts}, state ->
      plan
      |> search(term, opts, force?)
      |> Enum.reduce(state, fn result, state ->
        with false <- ReleaseRedFlags.suspicious?(result.title, result.size_bytes),
             false <- MapSet.member?(excluded, result.guid),
             false <- Map.has_key?(state.terms_by_guid, result.guid),
             {:ok, scope} <- TitleMatcher.coverage(result, identity) do
          %{
            state
            | options: [%Planner.Option{result: result, scope: scope} | state.options],
              terms_by_guid: Map.put(state.terms_by_guid, result.guid, term)
          }
        else
          _ -> state
        end
      end)
    end)
  end

  # Re-solves every floor group over the cumulative pool and recomputes
  # the residual. Rebuilt from scratch each rung — the planner is pure
  # and cheap, and a later rung's options only ever improve coverage.
  defp solve_groups(state, wanted, floor_groups, plan_prefs) do
    options = Enum.reverse(state.options)

    assignment_by_unit =
      Enum.reduce(floor_groups, %{}, fn {group_min, group_wanted}, acc ->
        solution = Planner.solve(group_wanted, options, %{plan_prefs | min_quality: group_min})

        for assignment <- solution.assignments,
            unit <- assignment.units,
            into: acc,
            do: {unit, assignment}
      end)

    %{
      state
      | assignment_by_unit: assignment_by_unit,
        residual: Enum.reject(wanted, &Map.has_key?(assignment_by_unit, &1))
    }
  end

  defp series_criteria(plan) do
    %Criteria{
      type: :tmdb,
      title: plan.title,
      tmdb_type: :tv,
      season_number: nil,
      episode_number: nil
    }
  end

  defp assignment_attrs(assignment, terms_by_guid) do
    %{
      assigned_guid: assignment.result.guid,
      assigned_title: assignment.result.title,
      assigned_term: Map.get(terms_by_guid, assignment.result.guid),
      assigned_quality: Quality.label(assignment.result.quality),
      assigned_seeders: assignment.result.seeders,
      assigned_size_bytes: assignment.result.size_bytes,
      assigned_scope: scope_label(assignment.scope)
    }
  end

  defp scope_label({:episode, season, episode}), do: "S#{pad(season)}E#{pad(episode)}"
  defp scope_label({:episodes, season, first, last}), do: "S#{pad(season)}E#{pad(first)}-#{pad(last)}"
  defp scope_label({:season, season}), do: "Season #{season} pack"
  defp scope_label({:seasons, first, last}), do: "Seasons #{first}–#{last} pack"
  defp scope_label(:series), do: "Complete series"
  defp scope_label(:unknown), do: nil

  # ---------------------------------------------------------------------------
  # Movies — one term, best acceptable pick
  # ---------------------------------------------------------------------------

  defp run_movie(plan, units, force?) do
    [{term, _opts}] = LadderTerms.for_plan(plan, [])
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

    best =
      plan
      |> search(term, [type: :movie], force?)
      |> Enum.filter(fn result ->
        not ReleaseRedFlags.suspicious?(result.title, result.size_bytes) and
          not MapSet.member?(excluded, result.guid) and
          TitleMatcher.matches?(result, criteria) and
          Quality.acceptable?(result.quality, min_quality, plan_prefs.max_quality)
      end)
      |> Enum.max_by(&{Quality.rank(&1.quality), &1.seeders || 0}, fn -> nil end)

    Enum.each(units, fn unit ->
      case best do
        nil ->
          {:ok, _} = Repo.update(PlanUnit.unfound_changeset(unit))

        result ->
          {:ok, _} =
            Repo.update(
              PlanUnit.assign_changeset(unit, %{
                assigned_guid: result.guid,
                assigned_title: result.title,
                assigned_term: term,
                assigned_quality: Quality.label(result.quality),
                assigned_seeders: result.seeders,
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

    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.acquisition_updates(), activity)

    case outcome do
      {:ok, results} ->
        results

      {:error, reason} ->
        Log.warning(:acquisition, "plan search failed — #{term} — #{inspect(reason)}")
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

    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.acquisition_updates(), status)
  end

  defp prefs(plan) do
    settings = AutoGrabSettings.load()
    criteria = plan.criteria || %{}

    %{
      min_quality: Map.get(criteria, "min_quality") || settings.default_min_quality,
      max_quality: Map.get(criteria, "max_quality") || settings.default_max_quality
    }
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
