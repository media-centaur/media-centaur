import Config

# Print only warnings and errors during test
config :logger, level: :warning

# Dedicated SQLite test database — separate from the dev/user database.
# The MIX_TEST_PARTITION environment variable supports CI test partitioning.
config :media_centarr, MediaCentarr.Repo,
  database:
    Path.expand(
      # We don't run a server during test. If one is required,
      # you can enable the server option below.
      "priv/repo/media_centarr_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      Path.dirname(__DIR__)
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :media_centarr, MediaCentarrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,

  # Oban inline testing — jobs execute synchronously in tests
  # Test-only signing key. Not a secret — tests never run against real data.
  # Never read user TOML config (~/.config/media-centarr/media-centarr.toml) in tests.
  # Tests use only app env defaults — no real user paths enter the test environment.
  secret_key_base: "test_signing_key_not_a_secret_deterministic_value_for_test_runs_xxxx"

config :media_centarr, Oban, testing: :inline

# Exercises the per-env compile-time default — `config/dev.exs` points
# at the dev TOML, prod falls back to the XDG path, test uses its own
# Use no-op HTTP client for image pipeline tests (avoids real downloads)
# sentinel path so `Config.config_path/0` tests can assert the routing
# Disable file watchers and Broadway pipeline in tests.
# mechanism end-to-end.
# Watchers start inotify on configured directories — not useful in tests and
# causes "kill: No such process" noise when the watched dir doesn't exist.
# The pipeline polls the DB every 2s and can trigger real TMDB HTTP requests.
config :media_centarr, :default_config_path, "~/.config/media-centarr/media-centarr-test.toml"
config :media_centarr, :environment, :test
config :media_centarr, :image_http_client, MediaCentarr.NoopImageDownloader
config :media_centarr, :skip_user_config, true
config :media_centarr, :start_pipeline, false
config :media_centarr, :start_watchers, false
config :media_centarr, :watch_dirs, []

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
