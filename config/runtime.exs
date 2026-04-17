import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if config_env() != :test do
  profile =
    case System.get_env("MEDIA_CENTARR_PROFILE") do
      nil -> nil
      "" -> nil
      name -> name
    end

  watch_dirs =
    case profile do
      nil ->
        [System.get_env("MEDIA_DIR", "/mnt/videos/Videos")]

      name ->
        # Profile's default watch_dir lives inside its data directory so
        # demo/feature-dev databases are fully isolated from the real library.
        profile_root = Path.expand("~/.local/share/media-centarr/profiles/#{name}")
        [System.get_env("MEDIA_DIR") || Path.join(profile_root, "media")]
    end

  config :media_centarr,
    watch_dirs: watch_dirs,
    tmdb_api_key: System.get_env("TMDB_API_KEY", ""),
    auto_approve_threshold: 0.85

  if profile do
    profile_root = Path.expand("~/.local/share/media-centarr/profiles/#{profile}")
    database_path = Path.join(profile_root, "media-centarr.db")

    config :media_centarr, MediaCentarr.Repo, database: database_path
  end
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise("environment variable SECRET_KEY_BASE is missing")

  config :media_centarr, MediaCentarrWeb.Endpoint,
    server: true,
    check_origin: false,
    http: [ip: {127, 0, 0, 1}, port: 4000],
    secret_key_base: secret_key_base
end
