ExUnit.start(capture_log: true)
ExUnit.configure(exclude: [:external])

# Start Credo's services so custom-check tests can use Credo.Test.Case helpers.
# Credo is `runtime: false`, so its application is not started automatically.
Application.ensure_all_started(:credo)

Ecto.Adapters.SQL.Sandbox.mode(MediaCentarr.Repo, :manual)
