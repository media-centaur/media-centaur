import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

if config_env() != :test do
  # Read the active TOML override once so we can hand both the Phoenix
  # Endpoint (port) and the Ecto Repo (database) their real values before
  # the supervision tree starts. `MEDIA_CENTAUR_CONFIG_OVERRIDE` is the
  # single lever — dev systemd unit, showcase seeder, and any demo setup
  # all set it to a self-contained TOML file. If unset, the default XDG
  # TOML is read (the installed production config).
  # Dev and prod have different default TOML paths so `iex -S mix phx.server`
  # in a dev checkout doesn't silently inherit the installed production's
  # config. The dev systemd unit also points at this same dev path via its
  # own `MEDIA_CENTAUR_CONFIG_OVERRIDE`.
  default_toml_path =
    if config_env() == :dev do
      "~/.config/media-centaur/media-centaur-dev.toml"
    else
      "~/.config/media-centaur/media-centaur.toml"
    end

  toml_path =
    case System.get_env("MEDIA_CENTAUR_CONFIG_OVERRIDE") do
      nil -> Path.expand(default_toml_path)
      "" -> Path.expand(default_toml_path)
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

  config :media_centaur, MediaCentaurWeb.Endpoint, http: [ip: {127, 0, 0, 1}, port: port]

  # Database: TOML `database_path` > compile-time default in config.exs.
  if db = get_in(toml, ["database_path"]) do
    config :media_centaur, MediaCentaur.Repo, database: Path.expand(db)
  end

  # Defaults that flow into MediaCentaur.Config as fallbacks — the TOML
  # overrides any of these via `watch_dirs`, `[tmdb].api_key`, etc.
  config :media_centaur,
    watch_dirs: [System.get_env("MEDIA_DIR", "/mnt/videos/Videos")],
    tmdb_api_key: System.get_env("TMDB_API_KEY", ""),
    auto_approve_threshold: 0.85

  # Incident-report submission inbox (observability Phase 3). A fine-grained
  # token scoped to `Issues:write` on a private reports repo turns on automatic
  # submission via `GithubTransport`. It is read here from the environment so it
  # never lands in the committed config or the user's plaintext TOML. With no
  # token set (the default), `GithubTransport` returns `{:error, :no_token}` and
  # the reporter falls back to a copyable bundle — so this is opt-in, and dev /
  # showcase / unconfigured installs never need it.
  if token = System.get_env("MEDIA_CENTAUR_DIAGNOSTICS_REPORT_TOKEN") do
    config :media_centaur, :diagnostics_report_token, token
  end

  if repo = System.get_env("MEDIA_CENTAUR_DIAGNOSTICS_REPORT_REPO") do
    config :media_centaur, :diagnostics_report_repo, repo
  end
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise("environment variable SECRET_KEY_BASE is missing")

  config :media_centaur, MediaCentaurWeb.Endpoint,
    server: true,
    check_origin: false,
    secret_key_base: secret_key_base
end
