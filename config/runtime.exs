import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if config_env() != :test do
  # Read the active TOML override once so we can hand both the Phoenix
  # Endpoint (port) and the Ecto Repo (database) their real values before
  # the supervision tree starts. `MEDIA_CENTARR_CONFIG_OVERRIDE` is the
  # single lever — dev systemd unit, showcase seeder, and any demo setup
  # all set it to a self-contained TOML file. If unset, the default XDG
  # TOML is read (the installed production config).
  toml_path =
    case System.get_env("MEDIA_CENTARR_CONFIG_OVERRIDE") do
      nil -> Path.expand("~/.config/media-centarr/media-centarr.toml")
      "" -> Path.expand("~/.config/media-centarr/media-centarr.toml")
      path -> Path.expand(path)
    end

  toml =
    with {:ok, contents} <- File.read(toml_path),
         {:ok, data} <- Toml.decode(contents) do
      data
    else
      _ -> %{}
    end

  # Port: env PORT > TOML `port` > env default (prod 2160, dev 1080).
  env_port = System.get_env("PORT")
  toml_port = get_in(toml, ["port"])

  port =
    cond do
      is_binary(env_port) and env_port != "" -> String.to_integer(env_port)
      is_integer(toml_port) -> toml_port
      config_env() == :prod -> 2160
      true -> 1080
    end

  config :media_centarr, MediaCentarrWeb.Endpoint, http: [ip: {127, 0, 0, 1}, port: port]

  # Database: TOML `database_path` > compile-time default in config.exs.
  if db = get_in(toml, ["database_path"]) do
    config :media_centarr, MediaCentarr.Repo, database: Path.expand(db)
  end

  # Defaults that flow into MediaCentarr.Config as fallbacks — the TOML
  # overrides any of these via `watch_dirs`, `[tmdb].api_key`, etc.
  config :media_centarr,
    watch_dirs: [System.get_env("MEDIA_DIR", "/mnt/videos/Videos")],
    tmdb_api_key: System.get_env("TMDB_API_KEY", ""),
    auto_approve_threshold: 0.85
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise("environment variable SECRET_KEY_BASE is missing")

  config :media_centarr, MediaCentarrWeb.Endpoint,
    server: true,
    check_origin: false,
    secret_key_base: secret_key_base
end
