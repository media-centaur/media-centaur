defmodule MediaCentarr.Acquisition.Pursuits.Snapshots do
  @moduledoc "Builder that assembles a Snapshot from live sources."

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Snapshot}
  alias MediaCentarr.Acquisition.QueueMonitor

  @doc """
  Assembles a Snapshot for the given pursuit. Reads the latest grab and
  the current queue snapshot side-by-side so Policy sees a coherent view.
  """
  @spec build(Pursuit.t()) :: Snapshot.t()
  def build(%Pursuit{} = pursuit) do
    %Snapshot{
      pursuit: pursuit,
      latest_grab: latest_grab(pursuit.id),
      queue_state: read_queue_state(),
      now: DateTime.utc_now(:second)
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
end
