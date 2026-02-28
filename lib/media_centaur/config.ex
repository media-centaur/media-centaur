defmodule MediaCentaur.Config do
  @moduledoc """
  Loads and serves application configuration from the user's
  TOML config file (`~/.config/media-centaur/backend.toml`),
  falling back to application environment defaults.

  Call `load!/0` once at startup (before the supervision tree).
  Use `get/1` anywhere to read a config key from `:persistent_term`.
  """
  require Logger

  @config_path "~/.config/media-centaur/backend.toml"

  @doc """
  Loads configuration from TOML and stores it in `:persistent_term`.
  Must be called once before any `get/1` calls — typically at the
  top of `Application.start/2`, before the children list.
  """
  def load! do
    config = load_config()
    :persistent_term.put({__MODULE__, :config}, config)
    :ok
  end

  def get(key) do
    :persistent_term.get({__MODULE__, :config}) |> Map.get(key)
  end

  defp load_config do
    defaults = %{
      database_path:
        expand(get_in(Application.get_env(:media_centaur, MediaCentaur.Repo), [:database])),
      watch_dirs: expand_list(Application.get_env(:media_centaur, :watch_dirs, [])),
      media_images_dir: expand(Application.get_env(:media_centaur, :media_images_dir)),
      tmdb_api_key: Application.get_env(:media_centaur, :tmdb_api_key),
      auto_approve_threshold: Application.get_env(:media_centaur, :auto_approve_threshold),
      mpv_path: "/usr/bin/mpv",
      mpv_socket_dir: "/tmp",
      mpv_socket_timeout_ms: 5000,
      exclude_dirs: [],
      extras_dirs: [
        "Extras",
        "Featurettes",
        "Special Features",
        "Behind The Scenes",
        "Bonus",
        "Deleted Scenes"
      ]
    }

    path = Path.expand(@config_path)

    case File.read(path) do
      {:ok, contents} ->
        case Toml.decode(contents) do
          {:ok, toml} ->
            merge_toml(defaults, toml)

          {:error, error} ->
            Logger.warning("Config: failed to parse #{path}: #{inspect(error)}, using defaults")
            defaults
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
      exclude_dirs: expand_list(get_in(toml, ["exclude_dirs"]) || defaults.exclude_dirs),
      media_images_dir: expand(get_in(toml, ["media_images_dir"]) || defaults.media_images_dir),
      tmdb_api_key: get_in(toml, ["tmdb", "api_key"]) || defaults.tmdb_api_key,
      auto_approve_threshold:
        get_in(toml, ["pipeline", "auto_approve_threshold"]) || defaults.auto_approve_threshold,
      mpv_path: get_in(toml, ["playback", "mpv_path"]) || defaults.mpv_path,
      mpv_socket_dir: get_in(toml, ["playback", "socket_dir"]) || defaults.mpv_socket_dir,
      mpv_socket_timeout_ms:
        get_in(toml, ["playback", "socket_timeout_ms"]) || defaults.mpv_socket_timeout_ms,
      extras_dirs: get_in(toml, ["pipeline", "extras_dirs"]) || defaults.extras_dirs
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
