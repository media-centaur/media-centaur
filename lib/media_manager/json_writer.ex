defmodule MediaManager.JsonWriter do
  use GenServer
  require Logger

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
  def handle_call({:write_entity, entity_id}, _from, state) do
    Logger.info("JsonWriter: write_entity stub called for #{entity_id}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:remove_entity, entity_id}, _from, state) do
    Logger.info("JsonWriter: remove_entity stub called for #{entity_id}")
    {:reply, :ok, state}
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

    json = Jason.encode!([], pretty: true)

    case File.write(tmp_path, json) do
      :ok ->
        case File.rename(tmp_path, media_json_path) do
          :ok ->
            Logger.info("JsonWriter: wrote #{media_json_path}")
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
