defmodule MediaManager.JsonWriter do
  use GenServer
  require Logger

  alias MediaManager.Library.{Entity, Serializer}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def write_entity(entity_id) do
    GenServer.call(__MODULE__, {:write_entity, entity_id})
  end

  def remove_entity(entity_id) do
    GenServer.call(__MODULE__, {:remove_entity, entity_id})
  end

  def regenerate_all(dir \\ nil) do
    GenServer.call(__MODULE__, {:regenerate_all, dir})
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:write_entity, _entity_id}, _from, state) do
    result = do_regenerate_all(MediaManager.Config.get(:shared_library_dir))
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_entity, _entity_id}, _from, state) do
    result = do_regenerate_all(MediaManager.Config.get(:shared_library_dir))
    {:reply, result, state}
  end

  @impl true
  def handle_call({:regenerate_all, dir}, _from, state) do
    result = do_regenerate_all(dir || MediaManager.Config.get(:shared_library_dir))
    {:reply, result, state}
  end

  @impl true
  def handle_info({:watcher_state_changed, _new_state}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:suspicious_burst, state) do
    {:noreply, state}
  end

  defp do_regenerate_all(shared_library_dir) do
    media_json_path = Path.join(shared_library_dir, "media.json")
    tmp_path = media_json_path <> ".tmp"

    File.mkdir_p!(shared_library_dir)

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
