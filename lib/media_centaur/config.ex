defmodule MediaCentaur.Config do
  @moduledoc """
  Loads and serves application configuration from the user's
  TOML config file (`~/.config/media-centaur/backend.toml`),
  falling back to application environment defaults.

  Call `load!/0` once at startup (before the supervision tree).
  Use `get/1` anywhere to read a config key from `:persistent_term`.
  """
  require MediaCentaur.Log, as: Log

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

  @doc "Returns the images directory for the given watch directory."
  @spec images_dir_for(String.t()) :: String.t()
  def images_dir_for(watch_directory) do
    get(:watch_dir_images)[watch_directory] ||
      default_images_dir(watch_directory)
  end

  @doc "Returns the staging base directory for in-progress image downloads."
  @spec staging_base_for(String.t()) :: String.t()
  def staging_base_for(watch_directory) do
    images_dir = images_dir_for(watch_directory)
    Path.join(images_dir, "partial-downloads")
  end

  @doc "Resolves a relative image content_url to an absolute filesystem path."
  @spec resolve_image_path(String.t() | nil) :: String.t() | nil
  def resolve_image_path(nil), do: nil

  def resolve_image_path(relative_content_url) do
    watch_dirs = get(:watch_dirs) || []

    Enum.find_value(watch_dirs, fn dir ->
      candidate = Path.join(images_dir_for(dir), relative_content_url)
      if File.regular?(candidate), do: candidate
    end)
  end

  defp load_config do
    app_watch_dirs = expand_list(Application.get_env(:media_centaur, :watch_dirs, []))
    {_, default_images_map} = parse_watch_dirs(app_watch_dirs)

    defaults = %{
      database_path:
        expand(get_in(Application.get_env(:media_centaur, MediaCentaur.Repo), [:database])),
      watch_dirs: app_watch_dirs,
      watch_dir_images: default_images_map,
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
      ],
      file_absence_ttl_days: 30
    }

    if Application.get_env(:media_centaur, :skip_user_config, false) do
      defaults
    else
      load_toml(defaults)
    end
  end

  defp load_toml(defaults) do
    path = Path.expand(@config_path)

    case File.read(path) do
      {:ok, contents} ->
        case Toml.decode(contents) do
          {:ok, toml} ->
            merge_toml(defaults, toml)

          {:error, error} ->
            Log.warning(
              :library,
              "failed to parse config #{path}: #{inspect(error)}, using defaults"
            )

            defaults
        end

      {:error, _} ->
        defaults
    end
  end

  defp merge_toml(defaults, toml) do
    {watch_dirs, watch_dir_images} = resolve_watch_dirs(toml, defaults)

    %{
      database_path: expand(get_in(toml, ["database_path"]) || defaults.database_path),
      watch_dirs: watch_dirs,
      watch_dir_images: watch_dir_images,
      exclude_dirs: expand_list(get_in(toml, ["exclude_dirs"]) || defaults.exclude_dirs),
      tmdb_api_key: get_in(toml, ["tmdb", "api_key"]) || defaults.tmdb_api_key,
      auto_approve_threshold:
        get_in(toml, ["pipeline", "auto_approve_threshold"]) || defaults.auto_approve_threshold,
      mpv_path: get_in(toml, ["playback", "mpv_path"]) || defaults.mpv_path,
      mpv_socket_dir: get_in(toml, ["playback", "socket_dir"]) || defaults.mpv_socket_dir,
      mpv_socket_timeout_ms:
        get_in(toml, ["playback", "socket_timeout_ms"]) || defaults.mpv_socket_timeout_ms,
      extras_dirs: get_in(toml, ["pipeline", "extras_dirs"]) || defaults.extras_dirs,
      file_absence_ttl_days:
        get_in(toml, ["file_absence_ttl_days"]) || defaults.file_absence_ttl_days
    }
  end

  # Supports plain string lists, inline table arrays, and legacy `media_dir` key.
  defp resolve_watch_dirs(toml, defaults) do
    case get_in(toml, ["watch_dirs"]) do
      dirs when is_list(dirs) and dirs != [] ->
        parse_watch_dirs(dirs)

      _ ->
        case get_in(toml, ["media_dir"]) do
          dir when is_binary(dir) ->
            dir = expand(dir)
            {[dir], %{dir => default_images_dir(dir)}}

          _ ->
            {defaults.watch_dirs, defaults.watch_dir_images}
        end
    end
  end

  defp parse_watch_dirs(raw_list) do
    Enum.reduce(raw_list, {[], %{}}, fn entry, {dirs, images_map} ->
      case entry do
        dir when is_binary(dir) ->
          dir = expand(dir)
          {[dir | dirs], Map.put(images_map, dir, default_images_dir(dir))}

        %{"dir" => dir} = table ->
          dir = expand(dir)
          images_dir = expand(table["images_dir"] || default_images_dir(dir))
          {[dir | dirs], Map.put(images_map, dir, images_dir)}
      end
    end)
    |> then(fn {dirs, images_map} -> {Enum.reverse(dirs), images_map} end)
  end

  defp default_images_dir(watch_dir), do: Path.join(watch_dir, ".media-centaur/images")

  defp expand(path) when is_binary(path), do: Path.expand(path)
  defp expand(path), do: path

  defp expand_list(paths) when is_list(paths), do: Enum.map(paths, &expand/1)
  defp expand_list(_), do: []
end
