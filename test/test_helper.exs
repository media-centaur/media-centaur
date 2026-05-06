ExUnit.start(capture_log: true)
ExUnit.configure(exclude: [:external])

# Start Credo's services so custom-check tests can use Credo.Test.Case helpers.
# Credo is `runtime: false`, so its application is not started automatically.
Application.ensure_all_started(:credo)

Ecto.Adapters.SQL.Sandbox.mode(MediaCentarr.Repo, :manual)

# Default to "wizard already dismissed" in tests so `SetupRedirect` doesn't
# divert every existing page-smoke test to /setup. Tests that exercise the
# redirect itself (`setup_redirect_test.exs`) flip this back to false in
# their own setup.
:persistent_term.put(
  {MediaCentarr.Config, :config},
  Map.put(
    :persistent_term.get({MediaCentarr.Config, :config}),
    :setup_wizard_dismissed,
    true
  )
)

# Prime the update-check cache so the Settings > Overview LiveView's
# auto-check-on-mount sees :fresh and does not dial out to GitHub during
# tests that haven't wired a stub. Tests that exercise the auto-check flow
# call `UpdateChecker.clear_cache/0` in their own setup.
MediaCentarr.SelfUpdate.UpdateChecker.cache_result({:error, :disabled_in_tests})
