# Dedicated SQLite test database — separate from the dev/user database.
# The MIX_TEST_PARTITION environment variable supports CI test partitioning.
import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :media_centarr, MediaCentarr.Repo,
  database:
    Path.expand(
      # We don't run a server during test. If one is required,
      # you can enable the server option below.
      "priv/repo/media_centarr_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      Path.dirname(__DIR__)
    ),

  # Oban inline testing — jobs execute synchronously in tests
  # Test-only signing key. Not a secret — tests never run against real data.
  # Never read user TOML config (~/.config/media-centarr/media-centarr.toml) in tests.
  # Exercises the per-env compile-time default — `config/dev.exs` points
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  # Bumped from the 2000ms default to absorb contention spikes when many
  # async test processes share the same DB file. The default occasionally
  # raised `Exqlite.Error: Database busy` from `Settings.put_*` writes
  # under load. See ~/src/media-centarr/flaky-tests.md (#1).
  busy_timeout: 10_000

config :media_centarr, MediaCentarrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  # Tests use only app env defaults — no real user paths enter the test environment.
  # at the dev TOML, prod falls back to the XDG path, test uses its own
  # Use no-op HTTP client for image pipeline tests (avoids real downloads)
  # sentinel path so `Config.config_path/0` tests can assert the routing
  # Disable file watchers and Broadway pipeline in tests.
  secret_key_base: "test_signing_key_not_a_secret_deterministic_value_for_test_runs_xxxx"

config :media_centarr, Oban, testing: :inline

# Bypass the BroadcastCoalescer in tests — concurrent tests would otherwise
# mechanism end-to-end.
# pollute each other's PubSub broadcasts via shared coalescer state. The
# Watchers start inotify on configured directories — not useful in tests and
# coalescer's own behavior is exercised directly in BroadcastCoalescerTest.
# causes "kill: No such process" noise when the watched dir doesn't exist.
# The pipeline polls the DB every 2s and can trigger real TMDB HTTP requests.
config :media_centarr, :coalesce_broadcasts?, false
config :media_centarr, :default_config_path, "~/.config/media-centarr/media-centarr-test.toml"
config :media_centarr, :environment, :test
config :media_centarr, :image_http_client, MediaCentarr.NoopImageDownloader
config :media_centarr, :skip_user_config, true
config :media_centarr, :start_pipeline, false
# Skip mpv socket recovery — otherwise the recovery task scans
# `mpv_socket_dir` (a real /tmp path on dev machines) and attaches to live
# mpv instances, leaking the user's playback session into every LiveView
# test that subscribes to playback events.
config :media_centarr, :start_playback_recovery, false
config :media_centarr, :start_watchers, false
config :media_centarr, :watch_dirs, []

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
