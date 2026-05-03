defmodule MediaCentarr.Acquisition.Jobs.SearchAndGrab do
  @moduledoc """
  Oban worker that searches Prowlarr for an acquisition target and grabs the
  best available result.

  ## Quality

  Releases below 1080p are filtered out. Among acceptable results 4K is preferred
  over 1080p (`Quality.rank/1`). Phase 2 will introduce per-grab quality bounds
  and the 4K-patience window.

  ## Lifecycle and snooze

      searching/snoozed ─► (acceptable result found) ─► grabbed
                       ─► (no acceptable result)     ─► snoozed (exp. backoff)
                       ─► (max attempts exceeded)    ─► abandoned
                       ─► (Prowlarr down)            ─► snoozed 1h, NO bump

  Exponential backoff: `min(4 * 2^(attempt - 1), 24)` hours, capped at 24h.
  Default `@max_attempts` is 12 — about a week at the cap.

  ## Cancellation

  The worker reads its grab row on every wake. Terminal-state grabs
  (`grabbed`, `cancelled`, `abandoned`) cause an immediate `:ok` early-exit
  with no Prowlarr call. This is how `Acquisition.cancel_grab/2` cuts a
  snoozed job short — it flips the row, the next wake sees it.
  """
  use Oban.Worker, queue: :acquisition, unique: [period: 300, keys: [:grab_id]]

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.{
    AutoGrabSettings,
    Grab,
    Prowlarr,
    QualityWindow,
    QueryBuilder,
    Quality,
    TitleMatcher
  }

  alias MediaCentarr.Repo

  @max_attempts 12
  @snooze_cap_hours 24
  @prowlarr_error_snooze_seconds 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"grab_id" => grab_id}}) do
    case Repo.get(Grab, grab_id) do
      nil -> {:ok, :not_found}
      %Grab{status: "grabbed"} -> {:ok, :already_grabbed}
      %Grab{status: "cancelled"} -> {:ok, :cancelled}
      %Grab{status: "abandoned"} -> {:ok, :abandoned}
      grab -> search_and_grab(grab)
    end
  end

  defp search_and_grab(grab) do
    Log.info(
      :library,
      "acquisition search — #{grab.title} (attempt #{grab.attempt_count + 1})"
    )

    bounds = effective_bounds(grab)

    case search_until_match(grab, QueryBuilder.build(grab), bounds) do
      {:ok, best} -> handle_found(grab, best)
      {:no_match, outcome} -> handle_no_results(grab, outcome)
      {:error, reason} -> handle_prowlarr_error(grab, reason)
    end
  end

  # Resolves the {effective_min, effective_max} the policy will enforce.
  # If the grab was snapshotted with bounds (Phase 2+), use them;
  # otherwise fall back to current global defaults (handles legacy rows).
  # The 4K-patience window can elevate the floor to "uhd_4k" while
  # the grab is young and max includes 4K.
  defp effective_bounds(grab) do
    settings = AutoGrabSettings.load()
    min = grab.min_quality || settings.default_min_quality
    max = grab.max_quality || settings.default_max_quality
    patience_hours = grab.quality_4k_patience_hours || settings.patience_hours

    snapshot = %{
      grab
      | min_quality: min,
        max_quality: max,
        quality_4k_patience_hours: patience_hours
    }

    {QualityWindow.min_at(snapshot, DateTime.utc_now()), max}
  end

  # Tries each candidate query in order. First acceptable hit wins.
  # On exhaustion, returns the most-informative outcome we observed.
  # A Prowlarr error short-circuits the loop.
  #
  # Outcomes (last one observed wins, except `no_results` is always
  # superseded since "we got something but rejected it" is more useful
  # diagnostically than "nothing came back"):
  #
  #   * `"no_results"`           — Prowlarr returned an empty list
  #   * `"no_title_match"`       — results came back but none parsed to
  #                                 the right show/movie (the bug fix
  #                                 introduced in TitleMatcher)
  #   * `"no_acceptable_quality"` — title matched but quality fell outside
  #                                  the configured bounds
  defp search_until_match(grab, queries, bounds) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Prowlarr.search(query, opts) do
        {:ok, []} ->
          {:cont, acc}

        {:ok, results} ->
          case best_match(results, grab, bounds) do
            {:found, best} -> {:halt, {:ok, best}}
            {:none, outcome} -> {:cont, {:no_match, outcome}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp best_match(results, grab, {min, max}) do
    matched = Enum.filter(results, &TitleMatcher.matches?(&1, grab))

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

  defp handle_found(grab, result) do
    case Prowlarr.grab(result) do
      :ok ->
        quality_label = Quality.label(result.quality)
        {:ok, updated} = Repo.update(Grab.grabbed_changeset(grab, quality_label))
        broadcast({:grab_submitted, updated})
        Log.info(:library, "acquisition grabbed #{quality_label} — #{grab.title}")
        {:ok, quality_label}

      {:error, reason} ->
        # Prowlarr accepted the search but the grab call failed — treat as
        # a "no acceptable result" outcome (the candidate was unsubmittable),
        # not as a Prowlarr-down failure. Still consumes a patience attempt.
        Log.warning(:library, "acquisition grab failed — #{inspect(reason)}")
        handle_no_results(grab, "grab_failed")
    end
  end

  defp handle_no_results(grab, outcome) do
    {:ok, updated} =
      grab
      |> Grab.attempt_changeset(outcome, snoozed: true)
      |> Repo.update()

    if updated.attempt_count >= @max_attempts do
      {:ok, abandoned} = Repo.update(Grab.abandoned_changeset(updated))
      broadcast({:auto_grab_abandoned, abandoned})
      Log.info(:library, "acquisition abandoned — #{grab.title} (#{@max_attempts} attempts)")
      :ok
    else
      broadcast({:auto_grab_snoozed, updated})

      Log.info(
        :library,
        "acquisition snooze — #{grab.title} (attempt #{updated.attempt_count})"
      )

      {:snooze, snooze_seconds(updated.attempt_count)}
    end
  end

  defp handle_prowlarr_error(grab, reason) do
    Log.warning(:library, "acquisition prowlarr error — #{inspect(reason)}")

    {:ok, updated} =
      grab
      |> Grab.infrastructure_failure_changeset("prowlarr_error")
      |> Repo.update()

    broadcast({:auto_grab_snoozed, updated})
    {:snooze, @prowlarr_error_snooze_seconds}
  end

  defp snooze_seconds(attempt_count) do
    hours = trunc(min(:math.pow(2, attempt_count - 1) * 4, @snooze_cap_hours))
    hours * 60 * 60
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.acquisition_updates(),
      message
    )
  end
end
