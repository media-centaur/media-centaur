defmodule MediaCentaur.Acquisition.Jobs.PursueTarget do
  @moduledoc """
  Oban worker that searches Prowlarr for a pursuit's recipe and either
  acquires the best matching release (TMDB recipe) or surfaces results
  to the user via the decision card (Prowlarr-query recipe).

  ## Recipe-polymorphic outcomes

  - **TMDB recipe** — Prowlarr results are TitleMatcher-filtered and
    Quality-bounded. Best acceptable hit transitions the target
    `seeking → acquired` and submits to the download client. No
    acceptable result snoozes the worker (exponential backoff) until
    `@max_attempts` is hit, at which point the target moves to
    `failed` and the pursuit to `exhausted`.
  - **Prowlarr-query recipe** — TitleMatcher is skipped (the user
    typed the query they trust). Any non-empty Prowlarr result set
    sets the pursuit's `awaiting_decision_at` flag so the user picks
    from the decision card. Empty results snooze and retry on the
    same schedule as TMDB.

  ## Quality

  Releases below the pursuit's `min_quality` are filtered out (TMDB
  recipe only). Among acceptable results 4K is preferred over 1080p
  (`Quality.rank/1`). Quality bounds live on the pursuit (in the
  `criteria` map).

  ## Lifecycle and snooze

      seeking ─► (acceptable TMDB result)         ─► acquired
              ─► (any Prowlarr-query result)      ─► (pursuit awaiting decision)
              ─► (no acceptable result)           ─► snoozed via Oban (exp. backoff)
              ─► (max attempts exceeded)          ─► failed
              ─► (Prowlarr down)                  ─► snoozed 1h, NO bump

  Exponential backoff: `min(4 * 2^(attempt - 1), 24)` hours, capped at 24h.
  Default `@max_attempts` is 12 — about a week at the cap.

  ## Cancellation

  The worker reads its target row on every wake. Terminal-state
  targets cause an immediate `:ok` early-exit with no Prowlarr call.
  This is how `Acquisition.cancel_target/2` cuts a snoozed job short
  — it flips the row, the next wake sees it.
  """
  use Oban.Worker, queue: :acquisition, unique: [period: 300, keys: [:target_id]]

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition

  alias MediaCentaur.Acquisition.{
    AutoGrabSettings,
    Corpus,
    Cours,
    InfoHash,
    Target,
    TargetEvents,
    TargetStatus
  }

  alias MediaCentaur.Search.{
    Criteria,
    Prowlarr,
    Quality,
    QueryBuilder,
    ReleasePreference,
    ReleaseRedFlags,
    SearchResult,
    TitleMatcher
  }

  alias MediaCentaur.Acquisition.Pursuits.{Commands, Pursuit, Recipe, State, Unit, UnitState, Units}
  alias MediaCentaur.Repo

  @max_attempts 12
  @snooze_cap_hours 24
  @prowlarr_error_snooze_seconds 60 * 60
  @needs_decision_prompt "Pick a release."

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"target_id" => target_id}}) do
    case load_target_with_pursuit(target_id) do
      {nil, _} ->
        {:ok, :not_found}

      {%Target{} = target, nil} ->
        Log.warning(:acquisition, "pursue_target: target #{target.id} has no pursuit; failing")
        {:ok, _failed} = Repo.update(Target.failed_changeset(target, "orphan_target"))
        {:ok, :no_pursuit}

      {%Target{} = target, %Pursuit{} = pursuit} ->
        dispatch(target, pursuit, covered_unit(target, pursuit))
    end
  end

  # Pursuit and unit state are checked before target status: the
  # aggregate is the authority. Never pursue on a terminal pursuit or a
  # terminal unit, even if the target row somehow survived as
  # `seeking`. Defense in depth — the terminal commands already cancel
  # in-flight targets, which the target-status guard below also
  # catches. This branch closes any remaining race window and any
  # future code path that creates a target on an already-closed goal.
  defp dispatch(%Target{} = target, %Pursuit{state: state} = pursuit, unit) do
    cond do
      State.terminal?(state) ->
        {:ok, :pursuit_terminal}

      match?(%Unit{}, unit) and UnitState.terminal?(unit.state) ->
        {:ok, :unit_terminal}

      TargetStatus.terminal?(target.status) ->
        {:ok, String.to_existing_atom(target.status)}

      true ->
        pursue(target, pursuit, unit)
    end
  end

  # One DB round-trip for both rows. Returns `{target_or_nil, pursuit_or_nil}`.
  defp load_target_with_pursuit(target_id) do
    query =
      from(t in Target,
        left_join: p in Pursuit,
        on: p.id == t.pursuit_id,
        where: t.id == ^target_id,
        select: {t, p}
      )

    case Repo.one(query) do
      nil -> {nil, nil}
      pair -> pair
    end
  end

  # The unit this target covers (exactly one until packs land —
  # ADR-055). Falls back to the pursuit's sole unit for legacy targets
  # without coverage rows.
  defp covered_unit(%Target{} = target, %Pursuit{} = pursuit) do
    case Units.covered_by(target.id) do
      [unit | _] -> unit
      [] -> Units.single!(pursuit.id)
    end
  end

  defp pursue(%Target{} = target, %Pursuit{} = pursuit, %Unit{} = unit) do
    Log.info(
      :acquisition,
      "acquisition search — #{target.title} (attempt #{target.attempt_count + 1})"
    )

    prefs = effective_prefs(pursuit)
    criteria = pursuit |> Recipe.for_unit(unit) |> Recipe.to_criteria() |> with_cour_run(pursuit, unit)

    case search_until_match(unit, criteria, QueryBuilder.build(criteria), prefs) do
      {:ok, best} -> handle_found(target, pursuit, best)
      {:needs_decision, _results} -> handle_needs_decision(target, pursuit, unit)
      {:no_match, outcome} -> handle_no_results(target, pursuit, outcome)
      {:error, reason} -> handle_prowlarr_error(target, reason)
    end
  end

  # Cour-aware re-search: when this TV unit belongs to a later broadcast
  # run, set the criteria's `run` so `QueryBuilder` emits run-shaped
  # queries (e.g. "Title 2nd Season") instead of the first-run "Season N"
  # — without it a committed later-cour release can't be re-found on
  # retry. One season fetch per attempt (a low-frequency seeking/retry
  # job); degrades to the regular queries on a TMDB error.
  defp with_cour_run(
         %Criteria{tmdb_type: :tv, season_number: season, episode_number: episode} = criteria,
         %Pursuit{tmdb_id: tmdb_id},
         _unit
       )
       when is_integer(season) and is_integer(episode) and is_binary(tmdb_id) do
    runs = Cours.runs_for_season(tmdb_id, season)
    %{criteria | run: Cours.later_run(runs, {season, episode})}
  end

  defp with_cour_run(%Criteria{} = criteria, _pursuit, _unit), do: criteria

  # Quality bounds live on the pursuit's `criteria` map, read as-is.
  # 4K patience is a want-ledger concern applied at plan time as a
  # quality-floor elevation (ADR-056 Q4) — the worker serves query-door
  # pursuits and failed-grab degradation, where the user already picked
  # the release, so a time-based floor has no meaning here.
  defp effective_prefs(%Pursuit{} = pursuit) do
    settings = AutoGrabSettings.load()
    criteria = pursuit.criteria || %{}

    %{
      min_quality: Map.get(criteria, "min_quality") || settings.default_min_quality,
      max_quality: Map.get(criteria, "max_quality") || settings.default_max_quality,
      size_preference: settings.size_preference
    }
  end

  @outcome_rank %{
    "no_results" => 0,
    "no_title_match" => 1,
    "no_acceptable_quality" => 2,
    "grab_failed" => 2
  }

  # Movie queries are alternate phrasings of ONE want; TV queries are a
  # narrowing ladder over a unit that is either covered or not. So movies
  # exhaust every query and keep the best, while TV still stops at the
  # first query that satisfies the unit. The two function names carry the
  # difference.
  defp search_until_match(unit, criteria, queries, prefs) do
    case {criteria.type, criteria.tmdb_type} do
      {:prowlarr_query, _tmdb_type} -> search_until_any_result(queries)
      {:tmdb, :movie} -> search_best_tmdb_match(unit, criteria, queries, prefs)
      {:tmdb, _tmdb_type} -> search_until_tmdb_match(unit, criteria, queries, prefs)
    end
  end

  # Searches go through the corpus (consult-first, ADR-055): a term
  # searched within the freshness window serves from durable knowledge
  # with zero indexer traffic — the snooze-retry loop is exactly the
  # automated caller the citizenship gate exists for.
  defp search_until_tmdb_match(unit, criteria, queries, prefs) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Corpus.search(query, opts) do
        {:ok, []} ->
          {:cont, acc}

        {:ok, results} ->
          case best_match(results, unit, criteria, prefs) do
            {:found, best} -> {:halt, {:ok, best}}
            {:none, outcome} -> {:cont, keep_more_informative(acc, outcome)}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # A movie's queries are `Title year` then the bare `Title`: release
  # groups tag a film with whichever year their source used, so the year
  # query routinely matches a handful of releases while every better copy
  # sits behind the year-less one. Halting on the first query that hit let
  # the year decide the quality ceiling — and nobody clicks "Find more" on
  # an unattended retry loop, so the worse copy stuck permanently. Ties
  # keep the earlier query's candidate (`ReleasePreference.better_of/3`),
  # so the year-matched term still wins against an equal candidate from
  # the broader one.
  defp search_best_tmdb_match(unit, criteria, queries, prefs) do
    queries
    |> Enum.reduce_while({{:no_match, "no_results"}, nil}, fn {query, opts}, {outcome, best} ->
      case Corpus.search(query, opts) do
        {:ok, []} ->
          {:cont, {outcome, best}}

        {:ok, results} ->
          case best_match(results, unit, criteria, prefs) do
            {:found, candidate} ->
              {:cont, {outcome, ReleasePreference.better_of(best, candidate, prefs.size_preference)}}

            {:none, degraded} ->
              {:cont, {keep_more_informative(outcome, degraded), best}}
          end

        {:error, reason} ->
          {:halt, {{:error, reason}, best}}
      end
    end)
    |> case do
      {{:error, _reason} = error, _best} -> error
      {_outcome, %SearchResult{} = best} -> {:ok, best}
      {outcome, nil} -> outcome
    end
  end

  defp search_until_any_result(queries) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Corpus.search(query, opts) do
        {:ok, []} -> {:cont, acc}
        {:ok, results} -> {:halt, {:needs_decision, results}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp keep_more_informative({:no_match, current} = acc, candidate) do
    if rank(candidate) > rank(current), do: {:no_match, candidate}, else: acc
  end

  defp rank(outcome), do: Map.get(@outcome_rank, outcome, 0)

  # Single-pass classifier over Prowlarr results. Projects the pursuit's
  # `%Recipe{}` once (instead of once per result) and folds the prior
  # `reject |> filter |> filter |> sort_by` chain into one `reduce`. The
  # outcome distinction "no_title_match" vs "no_acceptable_quality" is
  # preserved by upgrading the outcome the first time we see a
  # title-matching but quality-unacceptable result. Exclusions come
  # from the unit's thread (ADR-055).
  defp best_match(results, unit, criteria, prefs) do
    excluded = MapSet.new(unit.tried_release_guids || [])

    results
    |> Enum.reduce({nil, "no_title_match"}, fn result, {best, outcome} = acc ->
      cond do
        ReleaseRedFlags.suspicious?(result.title, result.size_bytes) ->
          acc

        MapSet.member?(excluded, result.guid) ->
          acc

        is_nil(criteria) or not TitleMatcher.matches?(result, criteria) ->
          acc

        not Quality.acceptable?(result.quality, prefs.min_quality, prefs.max_quality) ->
          {best, "no_acceptable_quality"}

        true ->
          {ReleasePreference.better_of(best, result, prefs.size_preference), outcome}
      end
    end)
    |> case do
      {nil, outcome} -> {:none, outcome}
      {%SearchResult{} = result, _outcome} -> {:found, result}
    end
  end

  defp handle_found(target, _pursuit, result) do
    case Prowlarr.grab(result) do
      :ok ->
        quality_label = Quality.label(result.quality)

        {:ok, updated} =
          Repo.update(
            Target.acquire_changeset(
              target,
              quality_label,
              result.title,
              result.guid,
              InfoHash.resolve(result)
            )
          )

        broadcast(%TargetEvents.Acquired{target: updated})
        Log.info(:acquisition, "acquisition acquired #{quality_label} — #{target.title}")
        {:ok, quality_label}

      {:error, reason} ->
        Log.warning(:acquisition, "acquisition grab failed — #{inspect(reason)}")
        pursuit = Repo.get(Pursuit, target.pursuit_id)
        handle_no_results(target, pursuit, "grab_failed")
    end
  end

  defp handle_needs_decision(target, pursuit, unit) do
    {:ok, _updated} = Repo.update(Target.attempt_changeset(target, "needs_decision"))

    case Commands.RequestDecision.execute(%{
           pursuit_id: pursuit.id,
           unit_id: unit.id,
           prompt: @needs_decision_prompt
         }) do
      {:ok, _pursuit} ->
        Log.info(
          :acquisition,
          "acquisition surfaced results — #{target.title} (Prowlarr query, awaiting pick)"
        )

        {:ok, :needs_decision}

      {:error, reason} ->
        Log.warning(:acquisition, "request_decision failed — #{inspect(reason)}")
        {:ok, :needs_decision_failed}
    end
  end

  defp handle_no_results(target, _pursuit, outcome) do
    {:ok, updated} =
      target
      |> Target.attempt_changeset(outcome)
      |> Repo.update()

    if updated.attempt_count >= @max_attempts do
      {:ok, failed} = Repo.update(Target.failed_changeset(updated, "exhausted"))
      broadcast(%TargetEvents.Failed{target: failed})
      Log.info(:acquisition, "acquisition exhausted — #{target.title} (#{@max_attempts} attempts)")
      :ok
    else
      seconds = snooze_seconds(updated.attempt_count)
      {:ok, scheduled} = persist_next_attempt(updated, seconds)
      broadcast(%TargetEvents.Snoozed{target: scheduled})

      Log.info(
        :acquisition,
        "acquisition snooze — #{target.title} (attempt #{scheduled.attempt_count})"
      )

      {:snooze, seconds}
    end
  end

  defp handle_prowlarr_error(target, reason) do
    Log.warning(:acquisition, "acquisition prowlarr error — #{inspect(reason)}")

    {:ok, updated} =
      target
      |> Target.infrastructure_failure_changeset("prowlarr_error")
      |> Repo.update()

    {:ok, scheduled} = persist_next_attempt(updated, @prowlarr_error_snooze_seconds)
    broadcast(%TargetEvents.Snoozed{target: scheduled})
    {:snooze, @prowlarr_error_snooze_seconds}
  end

  # Denormalises Oban's `scheduled_at` onto the target row so the read
  # path (pursuit status, row rendering) can show "next attempt in
  # 2h 15m" without querying Oban.
  defp persist_next_attempt(target, seconds) do
    next_at = DateTime.add(DateTime.utc_now(), seconds, :second)

    target
    |> Target.schedule_next_attempt_changeset(next_at)
    |> Repo.update()
  end

  defp snooze_seconds(attempt_count) do
    hours = trunc(min(:math.pow(2, attempt_count - 1) * 4, @snooze_cap_hours))
    hours * 60 * 60
  end

  defp broadcast(message), do: Acquisition.broadcast_update(message)
end
