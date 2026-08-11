defmodule MediaCentaur.ReleaseTracking.RetentionPolicies do
  @moduledoc """
  Retention policies owned by ReleaseTracking. Tracking events
  intentionally outlive their item (the FK nilifies on item delete), so
  a time window is the only bound on that log. Tracking artwork is
  covered by `MediaCentaur.TmdbArtwork.RetentionPolicies` — a tracked
  item is one kind of hold on that cache.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Retention.Policy

  @event_retention_days 90

  @impl true
  def policies do
    [
      %Policy{
        key: :release_tracking_events,
        subsystem: :acquisition,
        label: "Tracking activity log",
        description: "Deleted after #{@event_retention_days} days.",
        mode: :sweep,
        run: fn ->
          ReleaseTracking.prune_events(DateTime.add(DateTime.utc_now(), -@event_retention_days, :day))
        end
      }
    ]
  end
end
