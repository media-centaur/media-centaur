defmodule MediaCentaur.WatchHistory.RetentionPolicies do
  @moduledoc """
  Watch history is permanent, append-only by design (see
  `MediaCentaur.WatchHistory`) — titles are denormalized so events
  outlive their entities, and individual events are only ever removed by
  explicit user action. Declared as a `:forever` policy so the decision
  is visible on the Status page rather than implicit.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy

  @impl true
  def policies do
    [
      %Policy{
        key: :watch_history,
        subsystem: :playback,
        label: "Watch history",
        description:
          "Kept forever by design — history outlives deleted titles. " <>
            "Individual entries can be removed from the history page.",
        mode: :forever
      }
    ]
  end
end
