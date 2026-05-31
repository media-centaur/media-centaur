defmodule MediaCentaur.ErrorReports.PruneJob do
  @moduledoc """
  Daily retention prune for the durable diagnostic-event log.

  Deletes `diagnostic_events` older than the retention window (default 30 days)
  so the append-only log stays bounded. Incidents are never pruned here — they
  are the stateful records a report is built from and outlive their raw events.

  Scheduled by `Oban.Plugins.Cron` (see `config/config.exs`). The retention
  window can be overridden per-run via the `"retention_days"` job arg.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias MediaCentaur.ErrorReports.Store

  @default_retention_days 30
  @seconds_per_day 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    days = Map.get(args, "retention_days", @default_retention_days)
    cutoff = DateTime.add(DateTime.utc_now(), -days * @seconds_per_day, :second)

    {:ok, Store.prune_events(cutoff)}
  end
end
