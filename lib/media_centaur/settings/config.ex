defmodule MediaCentaur.Settings.Config do
  # `top_level?` keeps this a top-level boundary despite living in the
  # Settings namespace: a sub-boundary cannot disable checks, and Config
  # is deliberately `in: false` — every context reads it without
  # declaring a dep, same as before the move.
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Loads and serves application configuration.

  Configuration has two tiers with different sources of truth:

  * **Bootstrap state** — `database_path`, `port`, and the initial
    `media_dirs` seed. These are read from the user's TOML config file
    (`~/.config/media-centaur/media-centaur.toml`) because the app needs
    them before the database is reachable. They fall back to application
    environment defaults.
  * **Runtime preferences** — everything else (TMDB key, Prowlarr,
    download client, mpv/ffprobe paths, pipeline dirs, intervals, update
    flags, …). These live exclusively in the Settings database, are set
    in the app's Settings UI (or via `update/2`), and are overlaid onto
    `:persistent_term` by `load_runtime_overrides/0` once the Repo is up.
    Runtime keys are **not** read from TOML — a value left in the TOML
    for one is ignored, so the database is the single source of truth.

  Call `load!/0` once at startup (before the supervision tree).
  Use `get/1` anywhere to read a config key from `:persistent_term`.

  ## Sensitive values

  The keys listed in `sensitive_keys/0` are wrapped as
  `MediaCentaur.Secret` whenever they enter `:persistent_term`.
  `get/1` returns a `%Secret{}` for those keys; callers must use
  `Secret.expose/1` at the boundary where the raw value must be sent.
  This protects against crash-dump leaks (the entire config map is
  often included in `inspect/2` output of socket assigns) and is the
  minimum bar required by the sensitive-information policy ADR.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Secret
  alias MediaCentaur.Topics

  # Compile-time per-env default. `config/dev.exs` points at the dev
  # TOML so `iex -S mix phx.server` doesn't accidentally read the
  # installed production config and bind its port. `config/test.exs`
  # points at a sentinel path that the test suite asserts on. Prod
  # builds fall back to the XDG default.
  @default_config_path Application.compile_env(
                         :media_centaur,
                         :default_config_path,
                         "~/.config/media-centaur/media-centaur.toml"
                       )

  @sensitive_keys [
    :tmdb_api_key,
    :prowlarr_api_key,
    :download_client_password,
    :usenet_download_client_api_key,
    :nostr_secret_key
  ]

  # Runtime-settable keys: tunable via `update/2` and persisted to the
  # Settings DB. Excludes structural values (database_path, port,
  # media_dirs) that need a restart. Defined once as a module attribute
  # so the function and the `update/2` guard can't drift apart.
  @runtime_settable_keys [
    :tmdb_api_key,
    :auto_approve_threshold,
    :prowlarr_url,
    :prowlarr_api_key,
    :download_client_type,
    :download_client_url,
    :download_client_username,
    :download_client_password,
    :usenet_download_client_type,
    :usenet_download_client_url,
    :usenet_download_client_api_key,
    :mpv_path,
    :mpv_socket_dir,
    :mpv_socket_timeout_ms,
    :ffprobe_path,
    :file_absence_ttl_days,
    :recent_changes_days,
    :release_tracking_refresh_interval_hours,
    :release_tracking_sweep_interval_minutes,
    :extras_dirs,
    :skip_dirs,
    :exclude_dirs,
    :showcase_mode,
    :data_dir,
    :setup_wizard_dismissed,
    :update_check_enabled,
    :update_check_interval_minutes,
    :auto_update_enabled,
    :image_resolution,
    :nostr_secret_key
  ]

  # Artwork resolution preset (Settings → Pipeline). Governs the master
  # resolution backdrops are downloaded at — the only artwork shown full-bleed,
  # so the only one where 4K vs 1080p is visible. Posters/thumbnails are always
  # stored at a display-appropriate size and right-sized further by ImageServer.
  @image_resolutions ["4k", "1080p"]
  @image_resolution_default "4k"

  # Floor on the GitHub release-poll interval. The check hits the
  # unauthenticated GitHub API (~60 requests/hour per network IP), so a
  # tighter interval risks rate-limiting with no benefit — releases are
  # infrequent. Enforced on read so a stale/bad stored value can't
  # out-poll the limit.
  @update_check_interval_floor_minutes 15
  @update_check_interval_default_minutes 360

  @doc """
  Returns the absolute path to the active TOML config file.
  `MEDIA_CENTAUR_CONFIG_OVERRIDE` fully replaces the default — used by
  the dev systemd unit, the showcase seeder, and any other invocation
  that needs to point at a different TOML without touching the installed
  prod config.
  """
  @spec config_path() :: String.t()
  def config_path do
    case System.get_env("MEDIA_CENTAUR_CONFIG_OVERRIDE") do
      nil -> Path.expand(@default_config_path)
      "" -> Path.expand(@default_config_path)
      path -> Path.expand(path)
    end
  end

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
  The minimum minutes between background release checks, clamped up to
  the rate-limit floor. Read this rather than `get(:update_check_interval_minutes)`
  so the floor is always enforced, regardless of what's stored.
  """
  @spec update_check_interval_minutes() :: pos_integer()
  def update_check_interval_minutes do
    stored = get(:update_check_interval_minutes) || @update_check_interval_default_minutes
    max(@update_check_interval_floor_minutes, stored)
  end

  @doc "The rate-limit floor (minutes) for the release-check interval."
  @spec update_check_interval_floor_minutes() :: pos_integer()
  def update_check_interval_floor_minutes, do: @update_check_interval_floor_minutes

  @doc """
  The artwork resolution preset, one of #{inspect(@image_resolutions)}.
  Defaults to `"#{@image_resolution_default}"` and falls back to it for any
  unrecognised stored value, so a bad value can never break image downloads.

  The `:image_resolution_override` process-dict key takes precedence — the
  async-test injection seam, mirroring `ImageFiles.http_client/0`.
  """
  @spec image_resolution() :: String.t()
  def image_resolution do
    resolution = Process.get(:image_resolution_override) || get(:image_resolution)
    if resolution in @image_resolutions, do: resolution, else: @image_resolution_default
  end

  @doc "The valid artwork resolution presets, for UI rendering and validation."
  @spec image_resolutions() :: [String.t()]
  def image_resolutions, do: @image_resolutions

  @doc """
  The config keys that can be updated at runtime via `update/2` and
  persisted to the Settings database. Excludes structural values that
  require a restart (`database_path`, `media_dirs`, etc.).
  """
  def runtime_settable_keys, do: @runtime_settable_keys

  @doc "Keys whose values are wrapped in `MediaCentaur.Secret` (never logged or rendered)."
  @spec sensitive_keys() :: [atom()]
  def sensitive_keys, do: @sensitive_keys

  @doc """
  Loads runtime overrides from the Settings database and overlays them
  onto the `:persistent_term` config map. Call once after the Repo starts
  (i.e. after `Supervisor.start_link` returns in `Application.start/2`).
  Settings DB values take precedence over TOML values.

  Broadcasts `{:config_updated, key, value}` on `Topics.config_updates/0`
  for each key that was actually overlaid — symmetric with `update/2`,
  so derived caches (e.g. `Capabilities`) can subscribe once and react
  to both boot-time overlay and runtime updates through one channel.
  Keys without a stored override are silent (no broadcast).
  """
  def load_runtime_overrides do
    config = :persistent_term.get({__MODULE__, :config})

    keys = runtime_settable_keys()
    lookup_keys = Enum.map(keys, &"config:#{&1}")
    entries = MediaCentaur.Settings.get_by_keys(lookup_keys)

    {updated, overlaid} =
      Enum.reduce(keys, {config, []}, fn key, {acc, applied} ->
        case Map.get(entries, "config:#{key}") do
          %{value: %{"value" => value}} ->
            {Map.put(acc, key, maybe_wrap(key, value)), [{key, value} | applied]}

          _ ->
            {acc, applied}
        end
      end)

    :persistent_term.put({__MODULE__, :config}, updated)

    Enum.each(overlaid, fn {key, value} ->
      Topics.publish(
        Topics.config_updates(),
        {:config_updated, key, value}
      )
    end)

    :ok
  end

  defp maybe_wrap(key, value) do
    if key in @sensitive_keys, do: Secret.wrap(value), else: value
  end

  @doc """
  Updates a single runtime-settable config key: stores the new value in
  `:persistent_term` immediately (for zero-restart effect), persists it
  to the Settings database so it survives restarts, and broadcasts
  `{:config_updated, key, value}` on the config topic so subscribers can
  refresh any derived caches.
  """
  def update(key, value) when key in @runtime_settable_keys do
    config = :persistent_term.get({__MODULE__, :config})
    :persistent_term.put({__MODULE__, :config}, Map.put(config, key, maybe_wrap(key, value)))

    MediaCentaur.Settings.find_or_create_entry(%{
      key: "config:#{key}",
      value: %{"value" => value}
    })

    Topics.publish(
      Topics.config_updates(),
      {:config_updated, key, value}
    )

    :ok
  end

  @media_dirs_settings_key "config:media_dirs"

  @doc "Returns the raw list of media-dir entry maps from Settings."
  @spec media_dirs_entries() :: [map()]
  def media_dirs_entries do
    case MediaCentaur.Settings.get_by_key(@media_dirs_settings_key) do
      %{value: %{"entries" => entries}} when is_list(entries) -> entries
      _ -> []
    end
  end

  @doc """
  Replaces the entire media-dir list: persists to Settings, rebuilds the
  derived `:media_dirs` and `:media_dir_images` values in `:persistent_term`,
  and broadcasts `{:config_updated, :media_dirs, entries}` on the config topic.
  """
  @spec put_media_dirs([map()]) :: :ok
  def put_media_dirs(entries) when is_list(entries) do
    {:ok, _} =
      MediaCentaur.Settings.find_or_create_entry(%{
        key: @media_dirs_settings_key,
        value: %{"entries" => entries}
      })

    refresh_media_dirs_persistent_term(entries)

    Topics.publish(
      Topics.config_updates(),
      {:config_updated, :media_dirs, entries}
    )

    :ok
  end

  @doc "Subscribe the calling process to runtime config change broadcasts."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.config_updates())
  end

  @doc """
  One-shot import of TOML `media_dirs` into the Settings entry. No-op if the
  entry already exists. Called once per boot from `MediaCentaur.Application`.
  """
  @spec migrate_media_dirs_from_toml([map() | String.t()]) :: :ok
  def migrate_media_dirs_from_toml(toml_entries) when is_list(toml_entries) do
    case MediaCentaur.Settings.get_by_key(@media_dirs_settings_key) do
      %MediaCentaur.Settings.Entry{} ->
        :ok

      _ ->
        entries =
          toml_entries
          |> Enum.map(&normalize_toml_entry/1)
          |> Enum.reject(&is_nil/1)

        case entries do
          [] -> :ok
          list -> put_media_dirs(list)
        end
    end
  end

  @doc """
  Rebuilds `:media_dirs` and `:media_dir_images` in `:persistent_term` from
  the current Settings entry. Used on boot (after migration) and whenever a
  runtime change writes Settings directly.
  """
  @spec refresh_media_dirs_from_settings() :: :ok
  def refresh_media_dirs_from_settings do
    refresh_media_dirs_persistent_term(media_dirs_entries())
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
    Log.warning(:settings, "ignoring malformed media_dirs TOML entry: #{inspect(other)}")
    nil
  end

  defp new_uuid, do: Ecto.UUID.generate()

  defp refresh_media_dirs_persistent_term(entries) do
    dirs = Enum.map(entries, & &1["dir"])

    images_map =
      Map.new(
        Enum.filter(entries, &is_binary(&1["images_dir"])),
        fn entry -> {entry["dir"], entry["images_dir"]} end
      )

    config =
      :persistent_term.get({__MODULE__, :config})
      |> Map.put(:media_dirs, dirs)
      |> Map.put(:media_dir_images, images_map)

    :persistent_term.put({__MODULE__, :config}, config)
  end

  defp load_config do
    app_media_dirs = expand_list(Application.get_env(:media_centaur, :media_dirs, []))
    {_, default_images_map} = parse_media_dirs(app_media_dirs)

    database_path =
      expand(get_in(Application.get_env(:media_centaur, MediaCentaur.Repo), [:database]))

    # `data_dir` is the root for app-managed cache/storage that doesn't
    # live in the SQLite DB itself — currently just tracking-item images,
    # but the slot exists for future caches that need a writable home
    # independent of the user's media library. Defaults to the database's
    # parent directory so a stock install lays everything out under the
    # same XDG share root.
    default_data_dir = if database_path, do: Path.dirname(database_path)

    defaults = %{
      port: 2160,
      database_path: database_path,
      data_dir: default_data_dir,
      media_dirs: app_media_dirs,
      media_dir_images: default_images_map,
      tmdb_api_key: Secret.wrap(Application.get_env(:media_centaur, :tmdb_api_key)),
      auto_approve_threshold: Application.get_env(:media_centaur, :auto_approve_threshold),
      mpv_path: MediaCentaur.Platform.Defaults.mpv_path(),
      mpv_socket_dir: "/tmp",
      mpv_socket_timeout_ms: 5000,
      ffprobe_path: MediaCentaur.Platform.Defaults.ffprobe_path(),
      setup_wizard_dismissed: false,
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
      release_tracking_refresh_interval_hours: 6,
      release_tracking_sweep_interval_minutes: 15,
      prowlarr_url: nil,
      prowlarr_api_key: nil,
      download_client_type: nil,
      download_client_url: nil,
      download_client_username: nil,
      download_client_password: nil,
      usenet_download_client_type: nil,
      usenet_download_client_url: nil,
      usenet_download_client_api_key: nil,
      showcase_mode: false,
      update_check_enabled: true,
      update_check_interval_minutes: @update_check_interval_default_minutes,
      auto_update_enabled: false,
      # Social: this install's Nostr secret key (hex), generated on first use
      nostr_secret_key: nil
    }

    if Application.get_env(:media_centaur, :skip_user_config, false) do
      Application.put_env(:media_centaur, :__raw_toml_media_dirs, [])
      defaults
    else
      # `merge_toml/2` overrides only bootstrap keys, so runtime keys are
      # already at their defaults here — the DB overlay applies in
      # `load_runtime_overrides/0` once the Repo is up.
      load_toml(defaults)
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
              :settings,
              "failed to parse config #{path}: #{inspect(error)}, using defaults"
            )

            defaults
        end

      {:error, _} ->
        defaults
    end
  end

  defp merge_toml(defaults, toml) do
    {media_dirs, media_dir_images} = resolve_media_dirs(toml, defaults)

    Application.put_env(:media_centaur, :__raw_toml_media_dirs, toml_media_dirs(toml) || [])

    # Only bootstrap state is read from TOML: values the app needs before
    # the database is reachable (`database_path`, `port`) and the initial
    # `media_dirs` seed. Every runtime preference lives in the Settings
    # database and is overlaid by `load_runtime_overrides/0` — any runtime
    # key present in the TOML is intentionally ignored, so the DB is the
    # single source of truth and the TOML schema can't drift.
    Map.merge(defaults, %{
      port: get_in(toml, ["port"]) || defaults.port,
      database_path: expand(get_in(toml, ["database_path"]) || defaults.database_path),
      media_dirs: media_dirs,
      media_dir_images: media_dir_images
    })
  end

  # Supports plain string lists and inline table arrays. `media_dir_images`
  # carries only explicit `images_dir` overrides; the default layout is
  # `Library.ImageCache`'s.
  defp resolve_media_dirs(toml, defaults) do
    case toml_media_dirs(toml) do
      dirs when is_list(dirs) and dirs != [] ->
        parse_media_dirs(dirs)

      _ ->
        {defaults.media_dirs, defaults.media_dir_images}
    end
  end

  # The key was renamed from `watch_dirs` in 2026-06; a file still using
  # the old spelling stops the boot with the fix spelled out rather than
  # silently starting with no media directories.
  defp toml_media_dirs(toml) do
    if Map.has_key?(toml, "watch_dirs") do
      raise ArgumentError,
            "#{config_path()} uses the retired TOML key `watch_dirs`; rename it to `media_dirs`"
    end

    case get_in(toml, ["media_dirs"]) do
      dirs when is_list(dirs) -> dirs
      _ -> nil
    end
  end

  defp parse_media_dirs(raw_list) do
    {dirs, images_map} =
      Enum.reduce(raw_list, {[], %{}}, fn entry, {dirs, images_map} ->
        case entry do
          dir when is_binary(dir) ->
            {[expand(dir) | dirs], images_map}

          %{"dir" => dir, "images_dir" => images_dir} when is_binary(images_dir) ->
            dir = expand(dir)
            {[dir | dirs], Map.put(images_map, dir, expand(images_dir))}

          %{"dir" => dir} ->
            {[expand(dir) | dirs], images_map}
        end
      end)

    # `dirs` was prepended in the reduce; restore the source order.
    {Enum.reverse(dirs), images_map}
  end

  defp expand(path) when is_binary(path), do: Path.expand(path)
  defp expand(path), do: path

  defp expand_list(paths) when is_list(paths), do: Enum.map(paths, &expand/1)
  defp expand_list(_), do: []
end
