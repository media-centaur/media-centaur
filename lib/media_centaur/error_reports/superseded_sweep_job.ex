defmodule MediaCentaur.ErrorReports.SupersededSweepJob do
  @moduledoc """
  Daily maintenance sweep that auto-resolves open `:log` incidents belonging to
  a superseded app version.

  `:log` incidents (the safety net for unexpected, un-owned errors — including
  normal OTP supervised crash-and-restart) have no recovery signal: unlike
  `:subsystem` incidents, which the `Evaluator` resolves when their `assess/0`
  probe recovers, a `:log` incident is born `:open` and stays open forever. A
  deploy is the principled terminal signal — the binary that produced the error
  no longer runs, so the fault cannot recur in the same form. This job resolves
  those, keeping the incident board a view of *current* faults rather than an
  ever-growing archive. The rows are resolved, not deleted, so the audit trail
  survives.

  Scheduled by `Oban.Plugins.Cron` (see `config/config.exs`) on the
  `maintenance` queue alongside the retention prune. Idempotent — re-running
  resolves nothing once the superseded incidents are closed.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require MediaCentaur.Log

  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Log

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {count, _} =
      Store.resolve_superseded_log_incidents(EnvMetadata.app_version(), DateTime.utc_now())

    if count > 0 do
      Log.info(:system, "auto-resolved #{count} incident(s) from a superseded version")
    end

    {:ok, count}
  end
end
