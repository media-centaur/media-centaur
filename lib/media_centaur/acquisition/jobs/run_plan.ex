defmodule MediaCentaur.Acquisition.Jobs.RunPlan do
  @moduledoc """
  Oban worker that runs a draft plan's autonomous search-and-solve
  phase (media-search campaign Phase 3).

  One run walks the coverage ladder for the plan's wanted units —
  series term, per-wanted-season terms, per-unit episode terms — with
  every search going through the corpus (`Corpus.search/2`,
  consult-first citizenship; `force: true` only on a user-initiated
  re-search). Results are identity-verified (`TitleMatcher.coverage/2`),
  plan-wide exclusions filtered, and `Planner.solve/3` assigns
  candidates by the settled objective hierarchy. Assignments land on
  the plan units (found / unfound) and the plan transitions to `ready`
  for the user's steering pass.

  Movie plans skip the ladder: one term, best acceptable result by
  quality-then-seeders (`TitleMatcher.matches?/2` identity).

  Broadcasts `PlanEvents.SearchActivity` per term (the live activity
  feed) and `PlanEvents.Changed` when the rows move. Failures mark the
  plan's `error` and still transition to `ready` — a reported gap, not
  a stuck spinner.
  """

  use Oban.Worker, queue: :acquisition, unique: [period: 60, keys: [:plan_id]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{AutoGrabSettings, Corpus, PlanEvents, Planner, Plans}
  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{Criteria, Quality, TitleMatcher}
  alias MediaCentaur.Topics

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

    {options, terms_by_guid} = gather_options(plan, wanted, excluded, force?)

    solution = Planner.solve(wanted, options, prefs(plan))

    assignment_by_unit =
      for assignment <- solution.assignments,
          unit <- assignment.units,
          into: %{},
          do: {unit, assignment}

    Enum.each(units, fn unit ->
      key = {unit.season_number, unit.episode_number}

      case Map.get(assignment_by_unit, key) do
        nil ->
          {:ok, _} = Repo.update(PlanUnit.unfound_changeset(unit))

        assignment ->
          {:ok, _} =
            Repo.update(PlanUnit.assign_changeset(unit, assignment_attrs(assignment, terms_by_guid)))
      end
    end)
  end

  # Walks the ladder rungs broad-to-narrow. Every term goes through the
  # corpus; identity is verified per result; plan-wide exclusions are
  # dropped before solving (a release the user rejected for one episode
  # is almost never what they want for another).
  defp gather_options(plan, wanted, excluded, force?) do
    identity = series_criteria(plan)

    results_by_term =
      plan
      |> ladder_terms(wanted)
      |> Enum.map(fn {term, opts} -> {term, search(plan, term, opts, force?)} end)

    {options, terms_by_guid} =
      Enum.reduce(results_by_term, {[], %{}}, fn {term, results}, acc ->
        Enum.reduce(results, acc, fn result, {options, terms_by_guid} ->
          with false <- MapSet.member?(excluded, result.guid),
               false <- Map.has_key?(terms_by_guid, result.guid),
               {:ok, scope} <- TitleMatcher.coverage(result, identity) do
            {[%Planner.Option{result: result, scope: scope} | options],
             Map.put(terms_by_guid, result.guid, term)}
          else
            _ -> {options, terms_by_guid}
          end
        end)
      end)

    {Enum.reverse(options), terms_by_guid}
  end

  defp ladder_terms(plan, wanted) do
    seasons = wanted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

    series_terms = [{plan.title, [type: :tv]}]

    season_terms =
      Enum.flat_map(seasons, fn season ->
        [
          {"#{plan.title} Season #{season}", [type: :tv]},
          {"#{plan.title} S#{pad(season)}", [type: :tv]}
        ]
      end)

    episode_terms =
      Enum.map(wanted, fn {season, episode} ->
        {"#{plan.title} S#{pad(season)}E#{pad(episode)}", [type: :tv]}
      end)

    series_terms ++ season_terms ++ episode_terms
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
    term = if plan.year, do: "#{plan.title} #{plan.year}", else: plan.title
    excluded = units |> Enum.flat_map(& &1.excluded_release_guids) |> MapSet.new()

    criteria = %Criteria{type: :tmdb, title: plan.title, tmdb_type: :movie, year: plan.year}
    plan_prefs = prefs(plan)

    best =
      plan
      |> search(term, [type: :movie], force?)
      |> Enum.filter(fn result ->
        not MapSet.member?(excluded, result.guid) and
          TitleMatcher.matches?(result, criteria) and
          Quality.acceptable?(result.quality, plan_prefs.min_quality, plan_prefs.max_quality)
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
