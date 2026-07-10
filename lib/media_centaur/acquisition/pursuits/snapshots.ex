defmodule MediaCentaur.Acquisition.Pursuits.Snapshots do
  @moduledoc "Builder that assembles a Snapshot from live sources."

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Snapshot, Thresholds, Unit, Units}
  alias MediaCentaur.Acquisition.{QueueMatcher, Target}
  alias MediaCentaur.Downloads.{QueueItem, QueueMonitor}

  @doc """
  Assembles a Snapshot for the given pursuit + unit (ADR-055 — the
  watcher loop runs per unit). Reads the unit's current target, the
  current queue snapshot, and live thresholds side-by-side so Policy
  sees a coherent view. Derives `*_observed?` and `*_window_elapsed?`
  flags from the unit's persisted observation timestamps — those
  timestamps are kept current by `Pursuits.Observations.refresh!/4`,
  which the Watcher calls before invoking this builder.

  Pass an explicit `queue_state` (a `[QueueItem.t()]` list or `:unknown`)
  to reuse the same snapshot the Watcher already loaded — the 2-arity
  form reads it from `QueueMonitor`, which is convenient for tests but
  means one extra ETS read per unit on the watcher's hot path.
  """
  @spec build(Pursuit.t(), Unit.t()) :: Snapshot.t()
  def build(%Pursuit{} = pursuit, %Unit{} = unit), do: build(pursuit, unit, read_queue_state())

  @spec build(Pursuit.t(), Unit.t(), Snapshot.queue_state()) :: Snapshot.t()
  def build(%Pursuit{} = pursuit, %Unit{} = unit, queue_state),
    do: build(pursuit, unit, queue_state, Units.current_target(unit))

  @doc """
  Pre-fetched variant — accepts an already-loaded `current_target` (or
  `nil`) so the builder does not re-issue a `Repo.get/2` per call. Used
  by `Pursuits.Watcher` after batch-loading active units + their
  current targets in one go.
  """
  @spec build(Pursuit.t(), Unit.t(), Snapshot.queue_state(), Target.t() | nil) :: Snapshot.t()
  def build(%Pursuit{} = pursuit, %Unit{} = unit, queue_state, current_target) do
    now = DateTime.utc_now(:second)
    thresholds = Thresholds.load()

    %Snapshot{
      pursuit: pursuit,
      unit: unit,
      current_target: current_target,
      queue_state: queue_state,
      now: now,
      thresholds: thresholds,
      stall_observed?: not is_nil(unit.stall_first_seen_at),
      stall_window_elapsed?:
        window_elapsed?(unit.stall_first_seen_at, thresholds.stall_window_hours, now),
      zero_seeders_observed?: not is_nil(unit.zero_seeders_first_seen_at),
      zero_seeders_window_elapsed?:
        window_elapsed?(
          unit.zero_seeders_first_seen_at,
          thresholds.zero_seeders_window_hours,
          now
        ),
      download_failed?: download_failed?(queue_state, current_target)
    }
  end

  # The client itself declared the download terminally failed — only
  # drivers that report a failure detail set `failure_message` (SABnzbd's
  # `fail_message`: par2-unrepairable, unpack-failed). Gating on the
  # message, not just `state == :error`, keeps qBittorrent's ambiguous
  # `error`/`missingFiles` states (often user-moved files) out of the
  # auto-pivot path.
  defp download_failed?(:unknown, _target), do: false
  defp download_failed?(_queue, nil), do: false

  defp download_failed?(queue, %Target{} = target) when is_list(queue) do
    case QueueMatcher.find_item(queue, target.torrent_hash, target.release_title) do
      %QueueItem{state: :error, failure_message: message} when is_binary(message) -> true
      _ -> false
    end
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
