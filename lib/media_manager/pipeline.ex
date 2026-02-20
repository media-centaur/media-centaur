defmodule MediaManager.Pipeline do
  use Broadway
  require Logger

  alias MediaManager.Library.WatchedFile

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {MediaManager.Pipeline.Producer, []}, concurrency: 1],
      processors: [default: [concurrency: 3]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    file = message.data

    case process_file(file) do
      {:ok, _} ->
        message

      {:error, reason} ->
        Logger.warning("Pipeline: failed for #{file.id}: #{inspect(reason)}")
        Broadway.Message.failed(message, reason)
    end
  end

  defp process_file(file) do
    with {:ok, searched} <- search(file),
         :ok <- maybe_fetch_metadata(searched) do
      {:ok, searched}
    end
  end

  defp search(%WatchedFile{} = file) do
    Ash.update(file, %{}, action: :search)
  end

  defp maybe_fetch_metadata(%WatchedFile{state: :approved} = file) do
    with {:ok, fetched} <- Ash.update(file, %{}, action: :fetch_metadata) do
      export_library(fetched)
    end
  end

  defp maybe_fetch_metadata(%WatchedFile{}), do: :ok

  defp export_library(%WatchedFile{entity_id: entity_id}) when not is_nil(entity_id) do
    case MediaManager.JsonWriter.write_entity(entity_id) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp export_library(_file), do: :ok
end
