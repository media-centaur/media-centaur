defmodule MediaManager.JsonWriter do
  use GenServer
  require Logger

  alias MediaManager.Library.{Entity, Serializer}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def regenerate_all(path \\ nil) do
    GenServer.call(__MODULE__, {:regenerate_all, path})
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:regenerate_all, path}, _from, state) do
    result = do_regenerate_all(path || MediaManager.Config.get(:shared_media_library))
    {:reply, result, state}
  end

  defp do_regenerate_all(media_json_path) do
    tmp_path = media_json_path <> ".tmp"

    media_json_path |> Path.dirname() |> File.mkdir_p!()

    entities = Ash.read!(Entity, action: :with_associations)
    data = Serializer.serialize_all(entities)
    json = Jason.encode!(data, pretty: true)

    case File.write(tmp_path, json) do
      :ok ->
        case File.rename(tmp_path, media_json_path) do
          :ok ->
            Logger.info("JsonWriter: wrote #{media_json_path} (#{length(data)} entities)")
            :ok

          {:error, reason} ->
            Logger.error("JsonWriter: failed to rename tmp file: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("JsonWriter: failed to write tmp file: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
