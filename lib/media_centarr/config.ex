defmodule MediaCentarr.Config do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Loads and serves application configuration from the user's
  TOML config file (`~/.config/media-centarr/media-centarr.toml`),
  falling back to application environment defaults.

  Call `load!/0` once at startup (before the supervision tree).
  Use `get/1` anywhere to read a config key from `:persistent_term`.

  ## Sensitive values

  The keys listed in `sensitive_keys/0` are wrapped as
  `MediaCentarr.Secret` whenever they enter `:persistent_term`.
  `get/1` returns a `%Secret{}` for those keys; callers must use
  `Secret.expose/1` at the boundary where the raw value must be sent.
  This protects against crash-dump leaks (the entire config map is
  often included in `inspect/2` output of socket assigns) and is the
  minimum bar required by the sensitive-information policy ADR.
  """
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Secret

  @default_config_path "~/.config/media-centarr/media-centarr.toml"

  @sensitive_keys [:tmdb_api_key, :prowlarr_api_key, :download_client_password]

  @doc """
  Returns the absolute path to the active TOML config file.
  `MEDIA_CENTARR_CONFIG_OVERRIDE` fully replaces the default — used by
  the dev systemd unit, the showcase seeder, and any other invocation
  that needs to point at a different TOML without touching the installed
  prod config.
  """
  @spec config_path() :: String.t()
  def config_path do
    case System.get_env("MEDIA_CENTARR_CONFIG_OVERRIDE") do
      nil -> Path.expand(@default_config_path)
      "" -> Path.expand(@default_config_path)
      path -> Path.expand(path)
    end
  end

  @doc """
  Returns the list of config keys that must always be stored as
  `%Secret{}` in `:persistent_term`. Adding to this list also requires
  adding the key (or a substring match) to `:phoenix, :filter_parameters`
  in `config/config.exs`.
  """
  @spec sensitive_keys() :: [atom()]
  def sensitive_keys, do: @sensitive_keys

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
    Map.get(:persistent_term.get({__MODULE__, :config}), key)
  end

  @doc """
  The config keys that can be updated at runtime via `update/2` and
  persisted to the Settings database. Excludes structural values that
  require a restart (`database_path`, `watch_dirs`, etc.).
  """
  def runtime_settable_keys do
    [
      :tmdb_api_key,
      :auto_approve_threshold,
      :prowlarr_url,
      :prowlarr_api_key,
      :download_client_type,
      :download_client_url,
      :download_client_username,
      :download_client_password,
      :mpv_path,
      :mpv_socket_dir,
      :mpv_socket_timeout_ms,
      :file_absence_ttl_days,
      :recent_changes_days,
      :release_tracking_refresh_interval_hours,
      :extras_dirs,
      :skip_dirs,
      :exclude_dirs
    ]
  end

  @doc """
  Loads runtime overrides from the Settings database and overlays them
  onto the `:persistent_term` config map. Call once after the Repo starts
  (i.e. after `Supervisor.start_link` returns in `Application.start/2`).
  Settings DB values take precedence over TOML values.
  """
  def load_runtime_overrides do
    config = :persistent_term.get({__MODULE__, :config})

    updated =
      Enum.reduce(runtime_settable_keys(), config, fn key, acc ->
        case MediaCentarr.Settings.get_by_key("config:#{key}") do
          {:ok, %{value: %{"value" => value}}} -> Map.put(acc, key, maybe_wrap(key, value))
          _ -> acc
        end
      end)

    :persistent_term.put({__MODULE__, :config}, updated)
    :ok
  end

  defp maybe_wrap(key, value) do
    if key in @sensitive_keys, do: Secret.wrap(value), else: value
  end

  @doc """
  Updates a single runtime-settable config key: stores the new value in
  `:persistent_term` immediately (for zero-restart effect) and persists
  it to the Settings database so it survives restarts.
  """
  def update(key, value)
      when key in [
             :tmdb_api_key,
             :auto_approve_threshold,
             :prowlarr_url,
             :prowlarr_api_key,
             :download_client_type,
             :download_client_url,
             :download_client_username,
             :download_client_password,
             :mpv_path,
             :mpv_socket_dir,
             :mpv_socket_timeout_ms,
             :file_absence_ttl_days,
             :recent_changes_days,
             :release_tracking_refresh_interval_hours,
             :extras_dirs,
             :skip_dirs,
             :exclude_dirs
           ] do
    config = :persistent_term.get({__MODULE__, :config})
    :persistent_term.put({__MODULE__, :config}, Map.put(config, key, maybe_wrap(key, value)))

    MediaCentarr.Settings.find_or_create_entry(%{
      key: "config:#{key}",
      value: %{"value" => value}
    })

    :ok
  end

  @watch_dirs_settings_key "config:watch_dirs"

  @doc "Returns the raw list of watch-dir entry maps from Settings."
  @spec watch_dirs_entries() :: [map()]
  def watch_dirs_entries do
    case MediaCentarr.Settings.get_by_key(@watch_dirs_settings_key) do
      {:ok, %{value: %{"entries" => entries}}} when is_list(entries) -> entries
      _ -> []
    end
  end

  @doc """
  Replaces the entire watch-dir list: persists to Settings, rebuilds the
  derived `:watch_dirs` and `:watch_dir_images` values in `:persistent_term`,
  and broadcasts `{:config_updated, :watch_dirs, entries}` on the config topic.
  """
  @spec put_watch_dirs([map()]) :: :ok
  def put_watch_dirs(entries) when is_list(entries) do
    {:ok, _} =
      MediaCentarr.Settings.find_or_create_entry(%{
        key: @watch_dirs_settings_key,
        value: %{"entries" => entries}
      })

    refresh_watch_dirs_persistent_term(entries)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.config_updates(),
      {:config_updated, :watch_dirs, entries}
    )

    :ok
  end

  @doc "Subscribe the calling process to runtime config change broadcasts."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.config_updates())
  end

  @doc """
  One-shot import of any runtime-settable config keys present in TOML but
  absent from Settings. Called once per boot from `Application.init_services`.
  Idempotent — only writes keys that don't already have a Settings row.

  After this runs, the TOML is no longer consulted for runtime keys; the
  Settings database is the sole source of truth.
  """
  @spec migrate_runtime_keys_from_toml(map()) :: :ok
  def migrate_runtime_keys_from_toml(toml_runtime) when is_map(toml_runtime) do
    Enum.each(runtime_settable_keys(), fn key ->
      case MediaCentarr.Settings.get_by_key("config:#{key}") do
        {:ok, %MediaCentarr.Settings.Entry{}} ->
          :ok

        _ ->
          case Map.get(toml_runtime, key) do
            nil -> :ok
            value -> persist_migrated_value(key, value)
          end
      end
    end)

    :ok
  end

  defp persist_migrated_value(key, value) do
    # Sensitive keys arrive wrapped in %Secret{} — unwrap at the boundary
    # before persisting. Settings stores plaintext JSON and re-wraps on read
    # via load_runtime_overrides/0.
    raw =
      if key in @sensitive_keys do
        Secret.expose(value)
      else
        value
      end

    case raw do
      nil ->
        :ok

      "" ->
        :ok

      _ ->
        {:ok, _} =
          MediaCentarr.Settings.find_or_create_entry(%{
            key: "config:#{key}",
            value: %{"value" => raw}
          })

        :ok
    end
  end

  @doc """
  One-shot import of TOML `watch_dirs` into the Settings entry. No-op if the
  entry already exists. Called once per boot from `MediaCentarr.Application`.
  """
  @spec migrate_watch_dirs_from_toml([map() | String.t()]) :: :ok
  def migrate_watch_dirs_from_toml(toml_entries) when is_list(toml_entries) do
    case MediaCentarr.Settings.get_by_key(@watch_dirs_settings_key) do
      {:ok, %MediaCentarr.Settings.Entry{}} ->
        :ok

      _ ->
        entries =
          toml_entries
          |> Enum.map(&normalize_toml_entry/1)
          |> Enum.reject(&is_nil/1)

        case entries do
          [] -> :ok
          list -> put_watch_dirs(list)
        end
    end
  end

  @doc """
  Rebuilds `:watch_dirs` and `:watch_dir_images` in `:persistent_term` from
  the current Settings entry. Used on boot (after migration) and whenever a
  runtime change writes Settings directly.
  """
  @spec refresh_watch_dirs_from_settings() :: :ok
  def refresh_watch_dirs_from_settings do
    refresh_watch_dirs_persistent_term(watch_dirs_entries())
  end

  defp normalize_toml_entry(dir) when is_binary(dir) do
    %{"id" => new_uuid(), "dir" => Path.expand(dir), "images_dir" => nil, "name" => nil}
  end

  defp normalize_toml_entry(%{"dir" => dir} = table) do
    %{
      "id" => new_uuid(),
      "dir" => Path.expand(dir),
      "images_dir" => table["images_dir"] && Path.expand(table["images_dir"]),
      "name" => nil
    }
  end

  defp normalize_toml_entry(other) do
    Log.warning(:library, "ignoring malformed watch_dirs TOML entry: #{inspect(other)}")
    nil
  end

  defp new_uuid, do: Ecto.UUID.generate()

  defp refresh_watch_dirs_persistent_term(entries) do
    dirs = Enum.map(entries, & &1["dir"])

    images_map =
      Map.new(entries, fn entry ->
        dir = entry["dir"]
        images_dir = entry["images_dir"] || default_images_dir(dir)
        {dir, images_dir}
      end)

    config =
      :persistent_term.get({__MODULE__, :config})
      |> Map.put(:watch_dirs, dirs)
      |> Map.put(:watch_dir_images, images_map)

    :persistent_term.put({__MODULE__, :config}, config)
  end

  @doc "Returns the images directory for the given watch directory."
  @spec images_dir_for(String.t()) :: String.t()
  def images_dir_for(watch_directory) do
    get(:watch_dir_images)[watch_directory] ||
      default_images_dir(watch_directory)
  end

  @doc """
  Returns `{watch_dir, image_dir}` pairs where the image directory is NOT
  a subdirectory of its watch directory and therefore needs independent
  health monitoring.
  """
  @spec image_dirs_needing_monitoring() :: [{String.t(), String.t()}]
  def image_dirs_needing_monitoring do
    watch_dirs = get(:watch_dirs) || []

    Enum.flat_map(watch_dirs, fn watch_dir ->
      image_dir = images_dir_for(watch_dir)

      if String.starts_with?(image_dir, watch_dir <> "/") do
        []
      else
        [{watch_dir, image_dir}]
      end
    end)
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
    app_watch_dirs = expand_list(Application.get_env(:media_centarr, :watch_dirs, []))
    {_, default_images_map} = parse_watch_dirs(app_watch_dirs)

    database_path =
      expand(get_in(Application.get_env(:media_centarr, MediaCentarr.Repo), [:database]))

    defaults = %{
      port: 2160,
      database_path: database_path,
      watch_dirs: app_watch_dirs,
      watch_dir_images: default_images_map,
      tmdb_api_key: Secret.wrap(Application.get_env(:media_centarr, :tmdb_api_key)),
      auto_approve_threshold: Application.get_env(:media_centarr, :auto_approve_threshold),
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
      skip_dirs: ["Sample"],
      file_absence_ttl_days: 30,
      recent_changes_days: 3,
      release_tracking_refresh_interval_hours: 24,
      prowlarr_url: nil,
      prowlarr_api_key: nil,
      download_client_type: nil,
      download_client_url: nil,
      download_client_username: nil,
      download_client_password: nil
    }

    if Application.get_env(:media_centarr, :skip_user_config, false) do
      Application.put_env(:media_centarr, :__raw_toml_watch_dirs, [])
      Application.put_env(:media_centarr, :__raw_toml_runtime_keys, %{})
      defaults
    else
      toml_merged = load_toml(defaults)

      # Snapshot TOML-derived runtime-key values so the migration can
      # import them on first boot. After this point we revert those keys
      # to defaults so persistent_term is TOML-independent — the DB is
      # the runtime source of truth.
      runtime_snapshot =
        Map.new(runtime_settable_keys(), fn key -> {key, Map.get(toml_merged, key)} end)

      Application.put_env(:media_centarr, :__raw_toml_runtime_keys, runtime_snapshot)

      Enum.reduce(runtime_settable_keys(), toml_merged, fn key, acc ->
        Map.put(acc, key, Map.get(defaults, key))
      end)
    end
  end

  defp load_toml(defaults) do
    path = config_path()

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

    raw_watch_dirs =
      case get_in(toml, ["watch_dirs"]) do
        list when is_list(list) -> list
        _ -> []
      end

    Application.put_env(:media_centarr, :__raw_toml_watch_dirs, raw_watch_dirs)

    %{
      port: get_in(toml, ["port"]) || defaults.port,
      database_path: expand(get_in(toml, ["database_path"]) || defaults.database_path),
      watch_dirs: watch_dirs,
      watch_dir_images: watch_dir_images,
      exclude_dirs: expand_list(get_in(toml, ["exclude_dirs"]) || defaults.exclude_dirs),
      tmdb_api_key: Secret.wrap(get_in(toml, ["tmdb", "api_key"])) || defaults.tmdb_api_key,
      auto_approve_threshold:
        get_in(toml, ["pipeline", "auto_approve_threshold"]) || defaults.auto_approve_threshold,
      mpv_path: get_in(toml, ["playback", "mpv_path"]) || defaults.mpv_path,
      mpv_socket_dir: get_in(toml, ["playback", "socket_dir"]) || defaults.mpv_socket_dir,
      mpv_socket_timeout_ms:
        get_in(toml, ["playback", "socket_timeout_ms"]) || defaults.mpv_socket_timeout_ms,
      extras_dirs: get_in(toml, ["pipeline", "extras_dirs"]) || defaults.extras_dirs,
      skip_dirs: get_in(toml, ["pipeline", "skip_dirs"]) || defaults.skip_dirs,
      file_absence_ttl_days: get_in(toml, ["file_absence_ttl_days"]) || defaults.file_absence_ttl_days,
      recent_changes_days:
        get_in(toml, ["status", "recent_changes_days"]) || defaults.recent_changes_days,
      release_tracking_refresh_interval_hours:
        get_in(toml, ["release_tracking", "refresh_interval_hours"]) ||
          defaults.release_tracking_refresh_interval_hours,
      prowlarr_url: get_in(toml, ["prowlarr", "url"]),
      prowlarr_api_key: Secret.wrap(get_in(toml, ["prowlarr", "api_key"])),
      download_client_type: get_in(toml, ["download_client", "type"]),
      download_client_url: get_in(toml, ["download_client", "url"]),
      download_client_username: get_in(toml, ["download_client", "username"]),
      # Password is intentionally NOT read from TOML — it must be entered
      # via the Settings UI so it's never committed/backed up via dotfiles.
      download_client_password: nil
    }
  end

  # Supports plain string lists and inline table arrays.
  defp resolve_watch_dirs(toml, defaults) do
    case get_in(toml, ["watch_dirs"]) do
      dirs when is_list(dirs) and dirs != [] ->
        parse_watch_dirs(dirs)

      _ ->
        {defaults.watch_dirs, defaults.watch_dir_images}
    end
  end

  defp parse_watch_dirs(raw_list) do
    then(
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
      end),
      fn {dirs, images_map} -> {Enum.reverse(dirs), images_map} end
    )
  end

  defp default_images_dir(watch_dir), do: Path.join(watch_dir, ".media-centarr/images")

  defp expand(path) when is_binary(path), do: Path.expand(path)
  defp expand(path), do: path

  defp expand_list(paths) when is_list(paths), do: Enum.map(paths, &expand/1)
  defp expand_list(_), do: []
end
