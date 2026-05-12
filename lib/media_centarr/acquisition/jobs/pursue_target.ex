defmodule MediaCentarr.Acquisition.Jobs.PursueTarget do
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
    transitions the pursuit `active → needs_decision` so the user
    picks from the decision card. Empty results snooze and retry on
    the same schedule as TMDB.

  ## Quality

  Releases below the pursuit's `min_quality` are filtered out (TMDB
  recipe only). Among acceptable results 4K is preferred over 1080p
  (`Quality.rank/1`). Quality bounds live on the pursuit (in the
  `criteria` map).

  ## Lifecycle and snooze

      seeking ─► (acceptable TMDB result)         ─► acquired
              ─► (any Prowlarr-query result)      ─► (pursuit needs_decision)
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

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition

  alias MediaCentarr.Acquisition.{
    AutoGrabSettings,
    Prowlarr,
    QualityWindow,
    QueryBuilder,
    Quality,
    Target,
    TitleMatcher
  }

  alias MediaCentarr.Acquisition.Pursuits.{Commands, Pursuit}
  alias MediaCentarr.Repo

  @max_attempts 12
  @snooze_cap_hours 24
  @prowlarr_error_snooze_seconds 60 * 60
  @needs_decision_prompt "Pick a release."

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"target_id" => target_id}}) do
    case Repo.get(Target, target_id) do
      nil ->
        {:ok, :not_found}

      %Target{status: status} when status in ["acquired", "succeeded", "failed", "cancelled"] ->
        {:ok, String.to_existing_atom(status)}

      %Target{} = target ->
        pursue(target)
    end
  end

  defp pursue(%Target{} = target) do
    case Repo.get(Pursuit, target.pursuit_id) do
      %Pursuit{} = pursuit ->
        Log.info(
          :library,
          "acquisition search — #{target.title} (attempt #{target.attempt_count + 1})"
        )

        bounds = effective_bounds(pursuit)

        case search_until_match(target, pursuit, QueryBuilder.build(pursuit), bounds) do
          {:ok, best} -> handle_found(target, pursuit, best)
          {:needs_decision, _results} -> handle_needs_decision(target, pursuit)
          {:no_match, outcome} -> handle_no_results(target, pursuit, outcome)
          {:error, reason} -> handle_prowlarr_error(target, reason)
        end

      nil ->
        Log.warning(:library, "pursue_target: target #{target.id} has no pursuit; failing")
        {:ok, _failed} = Repo.update(Target.failed_changeset(target, "orphan_target"))
        {:ok, :no_pursuit}
    end
  end

  # Quality bounds live on the pursuit's `criteria` map. The
  # 4K-patience window can elevate the floor to "uhd_4k" while the
  # pursuit is young and max includes 4K.
  defp effective_bounds(%Pursuit{} = pursuit) do
    settings = AutoGrabSettings.load()
    criteria = pursuit.criteria || %{}
    min = Map.get(criteria, "min_quality") || settings.default_min_quality
    max = Map.get(criteria, "max_quality") || settings.default_max_quality
    patience_hours = Map.get(criteria, "quality_4k_patience_hours") || settings.patience_hours

    snapshot = %{
      min_quality: min,
      max_quality: max,
      quality_4k_patience_hours: patience_hours,
      inserted_at: pursuit.inserted_at
    }

    {QualityWindow.min_at(snapshot, DateTime.utc_now()), max}
  end

  @outcome_rank %{
    "no_results" => 0,
    "no_title_match" => 1,
    "no_acceptable_quality" => 2,
    "grab_failed" => 2
  }

  defp search_until_match(target, pursuit, queries, bounds) do
    case pursuit.recipe_type do
      "tmdb" -> search_until_tmdb_match(target, pursuit, queries, bounds)
      "prowlarr_query" -> search_until_any_result(queries)
    end
  end

  defp search_until_tmdb_match(_target, pursuit, queries, bounds) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Prowlarr.search(query, opts) do
        {:ok, []} ->
          {:cont, acc}

        {:ok, results} ->
          case best_match(results, pursuit, bounds) do
            {:found, best} -> {:halt, {:ok, best}}
            {:none, outcome} -> {:cont, keep_more_informative(acc, outcome)}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp search_until_any_result(queries) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Prowlarr.search(query, opts) do
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

  defp best_match(results, pursuit, {min, max}) do
    excluded = MapSet.new(pursuit.tried_release_guids || [])
    not_excluded = Enum.reject(results, fn result -> MapSet.member?(excluded, result.guid) end)
    matched = Enum.filter(not_excluded, &TitleMatcher.matches?(&1, pursuit))

    if matched == [] do
      {:none, "no_title_match"}
    else
      acceptable =
        matched
        |> Enum.filter(fn result -> Quality.acceptable?(result.quality, min, max) end)
        |> Enum.sort_by(fn result -> Quality.rank(result.quality) end, :desc)

      case acceptable do
        [] -> {:none, "no_acceptable_quality"}
        [best | _] -> {:found, best}
      end
    end
  end

  defp handle_found(target, _pursuit, result) do
    case Prowlarr.grab(result) do
      :ok ->
        quality_label = Quality.label(result.quality)

        {:ok, updated} =
          Repo.update(Target.acquire_changeset(target, quality_label, result.title, result.guid))

        broadcast({:target_acquired, updated})
        Log.info(:library, "acquisition acquired #{quality_label} — #{target.title}")
        {:ok, quality_label}

      {:error, reason} ->
        Log.warning(:library, "acquisition grab failed — #{inspect(reason)}")
        pursuit = Repo.get(Pursuit, target.pursuit_id)
        handle_no_results(target, pursuit, "grab_failed")
    end
  end

  defp handle_needs_decision(target, pursuit) do
    {:ok, _updated} = Repo.update(Target.attempt_changeset(target, "needs_decision"))

    case Commands.RequestDecision.execute(%{
           pursuit_id: pursuit.id,
           prompt: @needs_decision_prompt
         }) do
      {:ok, _pursuit} ->
        Log.info(
          :library,
          "acquisition surfaced results — #{target.title} (Prowlarr query, awaiting pick)"
        )

        {:ok, :needs_decision}

      {:error, reason} ->
        Log.warning(:library, "request_decision failed — #{inspect(reason)}")
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
      broadcast({:target_failed, failed})
      Log.info(:library, "acquisition exhausted — #{target.title} (#{@max_attempts} attempts)")
      :ok
    else
      seconds = snooze_seconds(updated.attempt_count)
      {:ok, scheduled} = persist_next_attempt(updated, seconds)
      broadcast({:target_snoozed, scheduled})

      Log.info(
        :library,
        "acquisition snooze — #{target.title} (attempt #{scheduled.attempt_count})"
      )

      {:snooze, seconds}
    end
  end

  defp handle_prowlarr_error(target, reason) do
    Log.warning(:library, "acquisition prowlarr error — #{inspect(reason)}")

    {:ok, updated} =
      target
      |> Target.infrastructure_failure_changeset("prowlarr_error")
      |> Repo.update()

    {:ok, scheduled} = persist_next_attempt(updated, @prowlarr_error_snooze_seconds)
    broadcast({:target_snoozed, scheduled})
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
