defmodule MediaCentarr.Pipeline.Import do
  @moduledoc """
  Broadway pipeline that fetches full metadata and publishes matched files
  to the library.

  Consumes `{:file_matched, ...}` events from both the Discovery pipeline
  (auto-matches) and Review (approved matches).

  Processing flow: parse → check disk space → fetch_metadata → publish.

  The Ingest stage broadcasts `{:entity_published, event}` to
  `"pipeline:publish"`. `Library.Inbound` subscribes and creates all
  library records, links files, and queues images.

  On completion, broadcasts `{:review_completed, pending_file_id}` to
  `"review:intake"` if the file came from a review approval.

  Broadway config: 1 producer (PubSub subscriber), 5 processors (partitioned
  by file path), 1 batcher (batch size 10, timeout 5s).

  See `docs/pipeline.md` for full architecture details.
  """
  use Broadway
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Parser
  alias MediaCentarr.Pipeline.{Payload, Stage}
  alias MediaCentarr.Pipeline.Stages.{FetchMetadata, Ingest}
  alias MediaCentarr.Storage

  @processor_concurrency 5
  @min_disk_bytes 100 * 1024 * 1024

  def processor_concurrency, do: @processor_concurrency

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaCentarr.Pipeline.Import.Producer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: @processor_concurrency, partition_by: &partition_key/1]],
      batchers: [default: [concurrency: 1, batch_size: 10, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    payload = message.data
    Log.info(:pipeline, "import — processing #{Path.basename(payload.file_path)}")

    case process(payload) do
      {:ok, payload} ->
        Log.info(:pipeline, "import — completed #{Path.basename(payload.file_path)}")
        Broadway.Message.update_data(message, fn _ -> payload end)

      {:error, reason} ->
        Log.warning(
          :pipeline,
          "import — failed for #{Path.basename(payload.file_path)}: #{inspect(reason)}"
        )

        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    messages
  end

  defp partition_key(%Broadway.Message{data: %Payload{file_path: path}}) do
    :erlang.phash2(path)
  end

  @doc """
  Processes a single payload through the Import pipeline.

  Parses the file path (for season/episode info), checks disk space,
  fetches full TMDB metadata, and ingests into the library.

  Returns `{:ok, payload}` or `{:error, reason}`.
  """
  def process(%Payload{} = payload) do
    payload = %{payload | parsed: Parser.parse(payload.file_path)}

    with :ok <- check_disk_space(payload.watch_directory),
         {:ok, payload} <- Stage.run(:fetch_metadata, FetchMetadata, payload),
         {:ok, payload} <- Stage.run(:ingest, Ingest, payload) do
      handle_complete(payload)
    end
  end

  defp check_disk_space(watch_directory) do
    images_dir = MediaCentarr.Config.images_dir_for(watch_directory)
    # df works on parent even if images_dir doesn't exist yet
    path = if File.dir?(images_dir), do: images_dir, else: watch_directory

    case Storage.available_bytes(path) do
      {:ok, avail} when avail < @min_disk_bytes ->
        Log.warning(
          :pipeline,
          "insufficient disk space: #{div(avail, 1_048_576)} MB available"
        )

        {:error, :insufficient_disk_space}

      _ ->
        :ok
    end
  end

  defp handle_complete(payload) do
    if payload.pending_file_id do
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.review_intake(),
        {:review_completed, payload.pending_file_id}
      )
    end

    {:ok, payload}
  end
end
