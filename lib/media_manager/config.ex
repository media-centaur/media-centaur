defmodule MediaManager.Config do
  use GenServer

  @config_path "~/.config/freedia-center/media-manager.toml"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @impl true
  def init(_) do
    config = load_config()
    {:ok, config}
  end

  @impl true
  def handle_call({:get, key}, _from, config) do
    {:reply, Map.get(config, key), config}
  end

  defp load_config do
    defaults = %{
      media_dir: expand(Application.get_env(:media_manager, :media_dir)),
      shared_media_library: expand(Application.get_env(:media_manager, :shared_media_library)),
      media_images_dir: expand(Application.get_env(:media_manager, :media_images_dir)),
      tmdb_api_key: Application.get_env(:media_manager, :tmdb_api_key),
      auto_approve_threshold: Application.get_env(:media_manager, :auto_approve_threshold)
    }

    path = Path.expand(@config_path)

    case File.read(path) do
      {:ok, contents} ->
        case Toml.decode(contents) do
          {:ok, toml} -> merge_toml(defaults, toml)
          {:error, _} -> defaults
        end

      {:error, _} ->
        defaults
    end
  end

  defp merge_toml(defaults, toml) do
    %{
      media_dir: expand(get_in(toml, ["media_dir"]) || defaults.media_dir),
      shared_media_library:
        expand(get_in(toml, ["shared_media_library"]) || defaults.shared_media_library),
      media_images_dir: expand(get_in(toml, ["media_images_dir"]) || defaults.media_images_dir),
      tmdb_api_key: get_in(toml, ["tmdb", "api_key"]) || defaults.tmdb_api_key,
      auto_approve_threshold:
        get_in(toml, ["pipeline", "auto_approve_threshold"]) || defaults.auto_approve_threshold
    }
  end

  defp expand(path) when is_binary(path), do: Path.expand(path)
  defp expand(path), do: path
end
