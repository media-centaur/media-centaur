import Config
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Dedicated SQLite test database — separate from the dev/user database.
# The MIX_TEST_PARTITION environment variable supports CI test partitioning.
config :media_manager, MediaManager.Repo,
  database:
    Path.expand(
      "priv/repo/media_manager_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      __DIR__ |> Path.dirname()
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :media_manager, MediaManagerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "drZ4av8PGWJfoIM6MU3ZMDBDopailIvJh5E5PmS/FgSegTMiyMWuhke/O0rXGulA",
  server: false

# In test we don't send emails
config :media_manager, MediaManager.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Use no-op image downloader in tests (avoids real HTTP + file I/O)
config :media_manager, :image_downloader, MediaManager.NoopImageDownloader
config :media_manager, :staging_image_downloader, MediaManager.NoopImageDownloader

# Disable file watchers and Broadway pipeline in tests.
# Watchers start inotify on configured directories — not useful in tests and
# causes "kill: No such process" noise when the watched dir doesn't exist.
# The pipeline polls the DB every 2s and can trigger real TMDB HTTP requests.
config :media_manager, :start_watchers, false
config :media_manager, :start_pipeline, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
