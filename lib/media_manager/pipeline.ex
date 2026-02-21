defmodule MediaManager.Pipeline do
  use Broadway
  require Logger

  alias MediaManager.Library.WatchedFile

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {MediaManager.Pipeline.Producer, []}, concurrency: 1],
      processors: [default: [concurrency: 3, partition_by: &partition_key/1]],
      batchers: [default: [concurrency: 1, batch_size: 10, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    file = message.data

    case process_file(file) do
      {:ok, processed} ->
        Broadway.Message.update_data(message, fn _ -> processed end)

      {:error, reason} ->
        Logger.warning("Pipeline: failed for #{file.id}: #{inspect(reason)}")
        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    has_entity =
      Enum.any?(messages, fn message ->
        match?(%WatchedFile{entity_id: entity_id} when not is_nil(entity_id), message.data)
      end)

    if has_entity do
      case MediaManager.JsonWriter.regenerate_all() do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Pipeline: batch JSON export failed: #{inspect(reason)}")
      end
    end

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
    Ash.update(file, %{}, action: :search)
  end

  defp maybe_fetch_metadata(%WatchedFile{state: :approved} = file) do
    Ash.update(file, %{}, action: :fetch_metadata)
  end

  defp maybe_fetch_metadata(%WatchedFile{} = file), do: {:ok, file}

  defp maybe_download_images(%WatchedFile{state: :fetching_images} = file) do
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
