defmodule MediaCentaur.Pipeline.Import do
  @moduledoc """
  Broadway pipeline that fetches full metadata and publishes matched files
  to the library.

  Consumes `{:file_matched, ...}` events from both the Discovery pipeline
  (auto-matches) and Review (approved matches).

  Processing flow: parse → check disk space → fetch_metadata → publish.

  The Ingest stage broadcasts `{:entity_published, event}` to
  `"pipeline:publish"`. `Library.Inbound` subscribes and creates all
  library records, links files, and queues images.

  On completion, destroys any associated PendingFile from Review.

  Broadway config: 1 producer (PubSub subscriber), 5 processors (partitioned
  by file path), 1 batcher (batch size 10, timeout 5s).

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser
  alias MediaCentaur.Pipeline.{Payload, Stage}
  alias MediaCentaur.Pipeline.Stages.{FetchMetadata, Ingest}
  alias MediaCentaur.Review
  alias MediaCentaur.Storage

  @processor_concurrency 5
  @min_disk_bytes 100 * 1024 * 1024

  def processor_concurrency, do: @processor_concurrency

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaCentaur.Pipeline.Import.Producer, []},
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
    images_dir = MediaCentaur.Config.images_dir_for(watch_directory)
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
      case Review.get_pending_file(payload.pending_file_id) do
        {:ok, pending_file} ->
          Review.destroy_pending_file!(pending_file)

          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            MediaCentaur.Topics.review_updates(),
            {:file_reviewed, payload.pending_file_id}
          )

        {:error, _} ->
          :ok
      end
    end

    {:ok, payload}
  end
end
