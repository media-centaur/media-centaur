ExUnit.start(capture_log: true)
ExUnit.configure(exclude: [:external])

# Start Credo's services so custom-check tests can use Credo.Test.Case helpers.
# Credo is `runtime: false`, so its application is not started automatically.
Application.ensure_all_started(:credo)

# Data migrations live under priv/repo/data_migrations/ and aren't on the
# normal compile path — the migrator loads them at runtime in production.
# Load them here so unit tests can reference each migration's helper functions
# directly (e.g. `BackfillOrphanedPursuits.backfill/1`) without compile-time
# undefined-module warnings.
:media_centaur
|> Application.app_dir("priv/repo/data_migrations")
|> Path.join("*.exs")
|> Path.wildcard()
|> Enum.each(&Code.require_file/1)

Ecto.Adapters.SQL.Sandbox.mode(MediaCentaur.Repo, :manual)

# Fake Nostr relays live here rather than under each test's supervisor so
# a relay outlives the clients its test started — see the teardown-order
# note in `MediaCentaur.Nostr.FakeRelay`.
{:ok, _} =
  DynamicSupervisor.start_link(name: MediaCentaur.Nostr.FakeRelay.Supervisor, strategy: :one_for_one)

# App-managed files (the TMDB artwork cache, app banners) live under
# `data_dir`, which defaults to the database's directory — `priv/repo` in
# test. Point it at a per-run tmp dir so no test writes into the repo tree
# (ADR-016); tests that assert on files still override it per test.
test_data_dir = Path.join(System.tmp_dir!(), "media_centaur_test_#{System.unique_integer([:positive])}")
File.mkdir_p!(test_data_dir)
ExUnit.after_suite(fn _result -> File.rm_rf!(test_data_dir) end)

# Default to "wizard already dismissed" in tests so `SetupRedirect` doesn't
# divert every existing page-smoke test to /setup. Tests that exercise the
# redirect itself (`setup_redirect_test.exs`) flip this back to false in
# their own setup.
:persistent_term.put(
  {MediaCentaur.Settings.Config, :config},
  Map.merge(
    :persistent_term.get({MediaCentaur.Settings.Config, :config}),
    %{setup_wizard_dismissed: true, data_dir: test_data_dir}
  )
)

# Prime the update-check cache so the Settings > Overview LiveView's
# auto-check-on-mount sees :fresh and does not dial out to GitHub during
# tests that haven't wired a stub. Tests that exercise the auto-check flow
# call `UpdateChecker.clear_cache/0` in their own setup.
MediaCentaur.SelfUpdate.UpdateChecker.cache_result({:error, :disabled_in_tests})

# Snapshot every app-owned :persistent_term key so DataCase can restore
# the lot before each test — the global caches the SQL sandbox cannot roll
# back. Must be the last thing this file does: the baseline is whatever
# state the priming above leaves behind, and that is what every test
# should start from. See `MediaCentaur.GlobalStateSandbox`.
MediaCentaur.GlobalStateSandbox.capture_pristine!()
