defmodule MediaCentaur.Acquisition.RetentionPolicies do
  @moduledoc """
  Retention policies owned by Acquisition. The pursuit ledger itself
  (pursuits, targets, units) is kept as durable bookkeeping; only the
  per-transition event log is bounded. The search corpus prunes itself
  on the 15-minute pursuit-watcher tick (`Corpus.prune_stale!/0`) and
  reports its runs — declared here so the Status page describes it.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Retention.Policy

  @pursuit_event_retention_days 90

  @impl true
  def policies do
    [
      %Policy{
        key: :pursuit_events,
        subsystem: :acquisition,
        label: "Pursuit activity log",
        description:
          "Events are deleted after #{@pursuit_event_retention_days} days; " <>
            "the pursuits themselves are kept.",
        mode: :sweep,
        run: fn ->
          Events.prune(DateTime.add(DateTime.utc_now(), -@pursuit_event_retention_days, :day))
        end
      },
      %Policy{
        key: :search_corpus,
        subsystem: :acquisition,
        label: "Search corpus",
        description: "Cached search results are deleted after #{Corpus.retention_days()} days.",
        mode: :external
      }
    ]
  end
end
