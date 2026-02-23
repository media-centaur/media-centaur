defmodule MediaManager.Pipeline do
  @moduledoc """
  Broadway pipeline that processes detected video files through search,
  metadata fetch, and image download stages.

  Processing flow per file: search → fetch_metadata → download_images → complete.
  Low-confidence matches stop at `:pending_review` for human approval.

  Broadway config: 1 producer (DB poller), 15 processors (partitioned by entity),
  1 batcher (serialises PubSub broadcasts, batch size 10, timeout 5s).

  See `PIPELINE.md` for full architecture details.
  """
  use Broadway
  require Logger
  require MediaManager.Log, as: Log

  alias MediaManager.Library.WatchedFile

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

      Phoenix.PubSub.broadcast(
        MediaManager.PubSub,
        "library:updates",
        {:entities_changed, entity_ids}
      )
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
    with {:ok, searched} <- search(file),
         {:ok, fetched} <- maybe_fetch_metadata(searched),
         {:ok, downloaded} <- maybe_download_images(fetched) do
      {:ok, downloaded}
    end
  end

  defp search(%WatchedFile{} = file) do
    result = Ash.update(file, %{}, action: :search)

    case result do
      {:ok, searched} ->
        Log.info(:pipeline, "post-search state: #{searched.state} for #{file.id}")

      _ ->
        :ok
    end

    result
  end

  defp maybe_fetch_metadata(%WatchedFile{state: :approved} = file) do
    Log.info(:pipeline, "fetching metadata for #{file.id}")
    Ash.update(file, %{}, action: :fetch_metadata)
  end

  defp maybe_fetch_metadata(%WatchedFile{} = file), do: {:ok, file}

  defp maybe_download_images(%WatchedFile{state: :fetching_images} = file) do
    Log.info(:pipeline, "downloading images for #{file.id}")

    case Ash.update(file, %{}, action: :download_images) do
      {:ok, downloaded} ->
        {:ok, downloaded}

      {:error, reason} ->
        Logger.warning("Pipeline: image download failed for #{file.id}: #{inspect(reason)}")
        {:ok, file}
    end
  end

  defp maybe_download_images(%WatchedFile{} = file), do: {:ok, file}
end
