ExUnit.start(capture_log: true)
ExUnit.configure(exclude: [:external])

# Start Credo's services so custom-check tests can use Credo.Test.Case helpers.
# Credo is `runtime: false`, so its application is not started automatically.
Application.ensure_all_started(:credo)

Ecto.Adapters.SQL.Sandbox.mode(MediaCentarr.Repo, :manual)

# Prime the update-check cache so the Settings > Overview LiveView's
# auto-check-on-mount sees :fresh and does not dial out to GitHub during
# tests that haven't wired a stub. Tests that exercise the auto-check flow
# call `UpdateChecker.clear_cache/0` in their own setup.
MediaCentarr.SelfUpdate.UpdateChecker.cache_result({:error, :disabled_in_tests})
