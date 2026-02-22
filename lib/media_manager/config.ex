defmodule MediaManager.Config do
  @moduledoc """
  GenServer that loads and serves application configuration from the user's
  TOML config file (`~/.config/freedia-center/media-manager.toml`),
  falling back to application environment defaults.
  """
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
      database_path:
        expand(get_in(Application.get_env(:media_manager, MediaManager.Repo), [:database])),
      watch_dirs: expand_list(Application.get_env(:media_manager, :watch_dirs, [])),
      shared_media_library: expand(Application.get_env(:media_manager, :shared_media_library)),
      media_images_dir: expand(Application.get_env(:media_manager, :media_images_dir)),
      tmdb_api_key: Application.get_env(:media_manager, :tmdb_api_key),
      auto_approve_threshold: Application.get_env(:media_manager, :auto_approve_threshold),
      mpv_path: "mpv",
      mpv_socket_dir: "/tmp",
      mpv_socket_timeout_ms: 5000,
      media_json_enabled: true
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
    watch_dirs = resolve_watch_dirs(toml, defaults)

    %{
      database_path: expand(get_in(toml, ["database_path"]) || defaults.database_path),
      watch_dirs: watch_dirs,
      shared_media_library:
        expand(get_in(toml, ["shared_media_library"]) || defaults.shared_media_library),
      media_images_dir: expand(get_in(toml, ["media_images_dir"]) || defaults.media_images_dir),
      tmdb_api_key: get_in(toml, ["tmdb", "api_key"]) || defaults.tmdb_api_key,
      auto_approve_threshold:
        get_in(toml, ["pipeline", "auto_approve_threshold"]) || defaults.auto_approve_threshold,
      mpv_path: get_in(toml, ["playback", "mpv_path"]) || defaults.mpv_path,
      mpv_socket_dir: get_in(toml, ["playback", "socket_dir"]) || defaults.mpv_socket_dir,
      mpv_socket_timeout_ms:
        get_in(toml, ["playback", "socket_timeout_ms"]) || defaults.mpv_socket_timeout_ms,
      media_json_enabled:
        case get_in(toml, ["media_json_enabled"]) do
          value when is_boolean(value) -> value
          _ -> defaults.media_json_enabled
        end
    }
  end

  # Supports both new `watch_dirs` (list) and old `media_dir` (string) keys in TOML.
  defp resolve_watch_dirs(toml, defaults) do
    case get_in(toml, ["watch_dirs"]) do
      dirs when is_list(dirs) and dirs != [] ->
        expand_list(dirs)

      _ ->
        case get_in(toml, ["media_dir"]) do
          dir when is_binary(dir) -> [expand(dir)]
          _ -> defaults.watch_dirs
        end
    end
  end

  defp expand(path) when is_binary(path), do: Path.expand(path)
  defp expand(path), do: path

  defp expand_list(paths) when is_list(paths), do: Enum.map(paths, &expand/1)
  defp expand_list(_), do: []
end
