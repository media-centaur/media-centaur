defmodule MediaCentarr.Acquisition.Pursuits.Snapshots do
  @moduledoc "Builder that assembles a Snapshot from live sources."

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Snapshot, Thresholds}
  alias MediaCentarr.Acquisition.QueueMonitor

  @doc """
  Assembles a Snapshot for the given pursuit. Reads the latest grab, the
  current queue snapshot, and live thresholds side-by-side so Policy
  sees a coherent view. Derives `*_observed?` and `*_window_elapsed?`
  flags from the pursuit's persisted observation timestamps — those
  timestamps are kept current by `Pursuits.Observations.refresh!/3`,
  which the Watcher calls before invoking this builder.
  """
  @spec build(Pursuit.t()) :: Snapshot.t()
  def build(%Pursuit{} = pursuit) do
    now = DateTime.utc_now(:second)
    thresholds = Thresholds.load()

    %Snapshot{
      pursuit: pursuit,
      latest_grab: latest_grab(pursuit.id),
      queue_state: read_queue_state(),
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

  defp latest_grab(pursuit_id) do
    case Pursuits.latest_grab(pursuit_id) do
      {:ok, grab} -> grab
      {:error, :not_found} -> nil
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
