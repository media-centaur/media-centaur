defmodule MediaManager.Pipeline do
  @moduledoc """
  Broadway pipeline that processes video files through search,
  metadata fetch, and image download stages.

  Processing flow: parse → search → fetch_metadata → download_images → ingest.
  Low-confidence matches stop at needs_review for human approval.

  The Producer delivers `%Payload{}` structs via PubSub events. This module
  processes them and creates WatchedFile records (`:link_file`) on completion
  or PendingFile records on needs_review.

  Broadway config: 1 producer (PubSub subscriber), 15 processors (partitioned
  by file path), 1 batcher (serialises PubSub broadcasts, batch size 10,
  timeout 5s).

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require Logger
  require MediaManager.Log, as: Log

  alias MediaManager.Library.{Helpers, WatchedFile}
  alias MediaManager.Parser
  alias MediaManager.Pipeline.Payload

  alias MediaManager.Pipeline.Stages.{
    Parse,
    Search,
    FetchMetadata,
    DownloadImages,
    Ingest
  }

  alias MediaManager.Review.{Intake, PendingFile}

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
    payload = message.data
    Log.info(:pipeline, "processing #{Path.basename(payload.file_path)}")

    case process_payload(payload) do
      {:ok, payload} ->
        Log.info(:pipeline, "completed #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:error, reason} ->
        Logger.warning(
          "Pipeline: failed for #{Path.basename(payload.file_path)}: #{inspect(reason)}"
        )

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

    messages
  end

  defp partition_key(%Broadway.Message{data: %Payload{file_path: path}}) do
    :erlang.phash2(path)
  end

  @doc false
  def process_payload(%Payload{entry_point: :file_detected} = payload) do
    if already_linked?(payload.file_path) do
      Log.info(:pipeline, "skipping already-linked file: #{Path.basename(payload.file_path)}")
      {:ok, payload}
    else
      case run_pipeline(payload) do
        {:ok, payload} -> handle_complete(payload)
        {:needs_review, payload} -> handle_needs_review(payload)
        {:error, reason} -> handle_error(payload, reason)
      end
    end
  end

  def process_payload(%Payload{entry_point: :review_resolved} = payload) do
    payload = %{payload | parsed: Parser.parse(payload.file_path)}

    case run_post_search(payload) do
      {:ok, payload} -> handle_complete(payload)
      {:error, reason} -> handle_error(payload, reason)
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

  defp handle_complete(payload) do
    WatchedFile
    |> Ash.Changeset.for_create(:link_file, %{
      file_path: payload.file_path,
      watch_dir: payload.watch_directory,
      entity_id: payload.entity_id
    })
    |> Ash.create!()

    if payload.pending_file_id do
      case Ash.get(PendingFile, payload.pending_file_id) do
        {:ok, pending_file} ->
          Ash.destroy!(pending_file)

          Phoenix.PubSub.broadcast(
            MediaManager.PubSub,
            "review:updates",
            {:file_reviewed, payload.pending_file_id}
          )

        {:error, _} ->
          :ok
      end
    end

    {:ok, payload}
  end

  defp handle_needs_review(payload) do
    Intake.create_from_payload(payload)
    {:ok, payload}
  end

  defp handle_error(_payload, reason) do
    {:error, reason}
  end

  defp already_linked?(file_path) do
    WatchedFile
    |> Ash.Query.do_filter(%{file_path: file_path})
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> case do
      [%WatchedFile{entity_id: entity_id}] when not is_nil(entity_id) -> true
      _ -> false
    end
  end
end
