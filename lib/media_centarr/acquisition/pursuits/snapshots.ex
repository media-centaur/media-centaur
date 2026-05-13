defmodule MediaCentarr.Acquisition.Pursuits.Snapshots do
  @moduledoc "Builder that assembles a Snapshot from live sources."

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Snapshot, Thresholds}
  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Downloads.QueueMonitor

  @doc """
  Assembles a Snapshot for the given pursuit. Reads the current target,
  the current queue snapshot, and live thresholds side-by-side so Policy
  sees a coherent view. Derives `*_observed?` and `*_window_elapsed?`
  flags from the pursuit's persisted observation timestamps — those
  timestamps are kept current by `Pursuits.Observations.refresh!/3`,
  which the Watcher calls before invoking this builder.

  Pass an explicit `queue_state` (a `[QueueItem.t()]` list or `:unknown`)
  to reuse the same snapshot the Watcher already loaded — the no-arg form
  reads it from `QueueMonitor`, which is convenient for tests but means
  one extra ETS read per pursuit on the watcher's hot path.
  """
  @spec build(Pursuit.t()) :: Snapshot.t()
  def build(%Pursuit{} = pursuit), do: build(pursuit, read_queue_state())

  @spec build(Pursuit.t(), Snapshot.queue_state()) :: Snapshot.t()
  def build(%Pursuit{} = pursuit, queue_state),
    do: build(pursuit, queue_state, Pursuits.current_target(pursuit))

  @doc """
  Pre-fetched variant — accepts an already-loaded `current_target` (or
  `nil`) so the builder does not re-issue a `Repo.get/2` per call. Used
  by `Pursuits.Watcher` after batch-loading active pursuits + their
  current targets in one go.
  """
  @spec build(Pursuit.t(), Snapshot.queue_state(), Target.t() | nil) :: Snapshot.t()
  def build(%Pursuit{} = pursuit, queue_state, current_target) do
    now = DateTime.utc_now(:second)
    thresholds = Thresholds.load()

    %Snapshot{
      pursuit: pursuit,
      current_target: current_target,
      queue_state: queue_state,
      now: now,
      thresholds: thresholds,
      stall_observed?: not is_nil(pursuit.stall_first_seen_at),
      stall_window_elapsed?:
        window_elapsed?(pursuit.stall_first_seen_at, thresholds.stall_window_hours, now),
      zero_seeders_observed?: not is_nil(pursuit.zero_seeders_first_seen_at),
      zero_seeders_window_elapsed?:
        window_elapsed?(
          pursuit.zero_seeders_first_seen_at,
          thresholds.zero_seeders_window_hours,
          now
        )
    }
  end

  defp read_queue_state do
    QueueMonitor.snapshot()
  rescue
    _ -> :unknown
  end

  defp window_elapsed?(nil, _hours, _now), do: false

  defp window_elapsed?(%DateTime{} = first_seen, hours, %DateTime{} = now) do
    DateTime.diff(now, first_seen, :second) >= hours * 3600
  end
end
