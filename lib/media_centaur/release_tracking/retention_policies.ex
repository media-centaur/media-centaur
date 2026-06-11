defmodule MediaCentaur.ReleaseTracking.RetentionPolicies do
  @moduledoc """
  Retention policies owned by ReleaseTracking. Tracking events
  intentionally outlive their item (the FK nilifies on item delete), so
  a time window is the only bound on that log. The artwork sweep removes
  `images/tracking/` directories whose item no longer exists.
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
        description: "Release-tracking events older than #{@event_retention_days} days are deleted.",
        mode: :sweep,
        run: fn ->
          ReleaseTracking.prune_events(DateTime.add(DateTime.utc_now(), -@event_retention_days, :day))
        end
      },
      %Policy{
        key: :tracking_artwork,
        subsystem: :acquisition,
        label: "Tracking artwork",
        description:
          "Artwork is removed with its tracked item; orphaned artwork folders are swept daily.",
        mode: :sweep,
        run: &ReleaseTracking.sweep_orphaned_artwork/0
      }
    ]
  end
end
