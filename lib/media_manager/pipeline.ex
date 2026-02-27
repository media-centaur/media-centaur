defmodule MediaManager.Pipeline do
  @moduledoc """
  Broadway pipeline that processes detected video files through search,
  metadata fetch, and image download stages.

  Processing flow per file: parse → search → fetch_metadata → download_images → ingest.
  Low-confidence matches stop at `:pending_review` for human approval.

  Broadway config: 1 producer (DB poller), 15 processors (partitioned by entity),
  1 batcher (serialises PubSub broadcasts, batch size 10, timeout 5s).

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require Logger
  require MediaManager.Log, as: Log

  alias MediaManager.Library.{Helpers, WatchedFile}
  alias MediaManager.Pipeline.Payload

  alias MediaManager.Pipeline.Stages.{
    Parse,
    Search,
    FetchMetadata,
    DownloadImages,
    Ingest
  }

  alias MediaManager.Review.Intake

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaManager.Pipeline.Producer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: 15, partition_by: &partition_key/1]],
      batchers: [default: [concurrency: 1, batch_size: 10, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    file = message.data
    Log.info(:pipeline, "processing #{file.id} (#{Path.basename(file.file_path)})")

    case process_file(file) do
      {:ok, processed} ->
        Log.info(:pipeline, "completed #{file.id}, state: #{processed.state}")
        Broadway.Message.update_data(message, fn _ -> processed end)

      {:error, reason} ->
        Logger.warning("Pipeline: failed for #{file.id}: #{inspect(reason)}")
        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    entity_ids =
      messages
      |> Enum.map(fn message -> message.data.entity_id end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if entity_ids != [] do
      Log.info(:pipeline, "batch complete, broadcasting #{length(entity_ids)} entity changes")
      Helpers.broadcast_entities_changed(entity_ids)
    end

    Phoenix.PubSub.broadcast(MediaManager.PubSub, "pipeline:updates", :pipeline_changed)

    messages
  end

  defp partition_key(%Broadway.Message{data: %WatchedFile{tmdb_id: tmdb_id}})
       when not is_nil(tmdb_id) do
    tmdb_id
  end

  defp partition_key(%Broadway.Message{data: %WatchedFile{id: id}}) do
    :erlang.phash2(id)
  end

  defp process_file(file) do
    payload = %Payload{
      file_path: file.file_path,
      watch_directory: file.watch_dir,
      entry_point: :file_detected
    }

    case run_pipeline(payload) do
      {:ok, payload} ->
        mark_complete(file, payload)

      {:needs_review, payload} ->
        send_to_review(file, payload)

      {:error, reason} ->
        mark_error(file, reason)
    end
  end

  defp run_pipeline(payload) do
    with {:ok, payload} <- Parse.run(payload),
         result <- Search.run(payload) do
      case result do
        {:ok, payload} -> run_post_search(payload)
        {:needs_review, _} = needs_review -> needs_review
        {:error, _} = error -> error
      end
    end
  end

  defp run_post_search(payload) do
    with {:ok, payload} <- FetchMetadata.run(payload),
         {:ok, payload} <- DownloadImages.run(payload),
         {:ok, payload} <- Ingest.run(payload) do
      {:ok, payload}
    end
  end

  defp mark_complete(file, payload) do
    Ash.update(file, %{state: :complete, entity_id: payload.entity_id}, action: :update_state)
  end

  defp send_to_review(file, payload) do
    Intake.create_from_payload(payload)
    Ash.update(file, %{state: :pending_review}, action: :update_state)
  end

  defp mark_error(file, reason) do
    Ash.update(file, %{state: :error, error_message: inspect(reason)}, action: :update_state)
  end
end
