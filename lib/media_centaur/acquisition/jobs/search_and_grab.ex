defmodule MediaCentaur.Acquisition.Jobs.SearchAndGrab do
  @moduledoc """
  Oban worker that searches Prowlarr for an acquisition target and grabs the
  best available result.

  Quality preference: 4K (`:uhd_4k`) > 1080p (`:hd_1080p`). Releases below
  1080p are filtered out. When nothing acceptable is found, the job snoozes
  for 4 hours and tries again. Once grabbed, further enqueues are no-ops.
  """
  use Oban.Worker, queue: :acquisition, unique: [period: 300, keys: ["grab_id"]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{Grab, Prowlarr, Quality}
  alias MediaCentaur.Repo

  @retry_interval_seconds 4 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"grab_id" => grab_id}}) do
    case Repo.get(Grab, grab_id) do
      nil ->
        {:ok, :not_found}

      %Grab{status: "grabbed"} ->
        {:ok, :already_grabbed}

      grab ->
        search_and_grab(grab)
    end
  end

  defp search_and_grab(grab) do
    Log.info(:library, "acquisition search — #{grab.title} (attempt #{grab.attempt_count + 1})")

    case Prowlarr.search(grab.title) do
      {:ok, results} ->
        case best_acceptable(results) do
          nil ->
            handle_not_found(grab)

          best ->
            handle_found(grab, best)
        end

      {:error, reason} ->
        Log.warning(:library, "acquisition search error — #{inspect(reason)}")
        handle_not_found(grab)
    end
  end

  defp best_acceptable(results) do
    results
    |> Enum.filter(fn result -> Quality.acceptable?(result.quality) end)
    |> Enum.sort_by(fn result -> Quality.rank(result.quality) end, :desc)
    |> List.first()
  end

  defp handle_found(grab, result) do
    case Prowlarr.grab(result) do
      :ok ->
        quality_label = Quality.label(result.quality)

        {:ok, updated} =
          grab
          |> Grab.grabbed_changeset(quality_label)
          |> Repo.update()

        broadcast({:grab_submitted, updated})
        Log.info(:library, "acquisition grabbed #{quality_label} — #{grab.title}")
        {:ok, quality_label}

      {:error, reason} ->
        Log.warning(:library, "acquisition grab failed — #{inspect(reason)}")
        handle_not_found(grab)
    end
  end

  defp handle_not_found(grab) do
    {:ok, updated} =
      grab
      |> Grab.increment_attempt_changeset()
      |> Repo.update()

    broadcast({:search_retry_scheduled, updated})

    Log.info(
      :library,
      "acquisition retry scheduled — #{grab.title} (attempt #{updated.attempt_count})"
    )

    {:snooze, @retry_interval_seconds}
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.acquisition_updates(),
      message
    )
  end
end
