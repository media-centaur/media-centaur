defmodule MediaCentaur.Pipeline.Import do
  @moduledoc """
  Broadway pipeline that fetches full metadata and publishes matched files
  to the library.

  Consumes `{:file_matched, ...}` events from both the Discovery pipeline
  (auto-matches) and Review (approved matches).

  Processing flow: parse → check disk space → fetch_metadata → publish.

  The Ingest stage broadcasts `{:entity_published, event}` to
  `"pipeline:publish"`. `Library.Inbound` subscribes and creates all
  library records, links files, queues images, and reports the file's
  link outcome on `"library:file_events"`.

  An import that fails before publishing never reaches the library, so
  `handle_failed/2` reports that outcome itself —
  `{:file_not_linked, %{reason: {:import_failed, reason}}}` on the same
  topic. Every match therefore ends in exactly one link outcome, which is
  what `Review` closes and reopens its items on.

  Broadway config: 1 producer (PubSub subscriber), 5 processors (partitioned
  by file path), no batcher — each message acks after `handle_message`.

  See `docs/pipeline.md` for full architecture details.
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Parser

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Pipeline.{Payload, Stage}
  alias MediaCentaur.Pipeline.Stages.{FetchMetadata, Ingest}
  alias MediaCentaur.Settings.Config
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
      processors: [default: [concurrency: @processor_concurrency, partition_by: &partition_key/1]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    payload = message.data
    Log.info(:pipeline, "import — processing #{Path.basename(payload.file_path)}")

    case process_payload(payload) do
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

  # Every failed message — an `{:error, _}` from `process_payload/1` or an
  # exception Broadway caught — ends here. The file never reached the
  # library, so this is its link outcome.
  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn %Broadway.Message{data: payload, status: status} ->
      report_not_linked(payload, failure_reason(status))
    end)

    messages
  end

  defp failure_reason({:failed, reason}), do: reason

  defp failure_reason({kind, reason, _stacktrace}) when kind in [:error, :throw, :exit],
    do: {kind, reason}

  defp report_not_linked(%Payload{file_path: file_path, media_directory: media_dir}, reason) do
    MediaCentaur.Topics.publish(
      MediaCentaur.Topics.library_file_events(),
      {:file_not_linked, %{file_path: file_path, media_dir: media_dir, reason: {:import_failed, reason}}}
    )
  end

  defp partition_key(%Broadway.Message{data: %Payload{file_path: path}}) do
    :erlang.phash2(path)
  end

  @doc """
  Processes a single payload through the Import pipeline.

  Parses the file path, places it at the match's season and episode,
  checks disk space, fetches full TMDB metadata, and ingests into the
  library.

  Returns `{:ok, payload}` or `{:error, reason}`.
  """
  def process_payload(%Payload{} = payload) do
    # The payload arrives over `pipeline:matched` from Discovery or a
    # review approval, built by `Import.Producer.build_payload/1`, which
    # carries no parse — so this stage parses for what the match does not
    # say (bonus feature or not, its parent). It has to use the same extras
    # setting as the stage that classified the file, or the same path is a
    # title to one and a bonus feature to the other. The season and episode
    # are the match's, not the path's.
    parsed = Parser.parse(payload.file_path, extras_dirs: Config.extras_dirs())
    parsed = %{parsed | season: payload.match_season, episode: payload.match_episode}
    payload = %{payload | parsed: parsed}

    with :ok <- check_disk_space(payload.media_directory),
         {:ok, payload} <- Stage.run(:fetch_metadata, FetchMetadata, payload) do
      Stage.run(:ingest, Ingest, payload)
    end
  end

  defp check_disk_space(media_directory) do
    images_dir = ImageCache.dir_for(media_directory)
    # df works on parent even if images_dir doesn't exist yet
    path = if File.dir?(images_dir), do: images_dir, else: media_directory

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
end
