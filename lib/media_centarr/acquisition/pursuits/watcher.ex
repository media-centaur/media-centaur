defmodule MediaCentarr.Acquisition.Pursuits.Watcher do
  @moduledoc """
  Periodic orchestrator driving Policy for every active pursuit.

  Each tick:

    1. Reads the current download-client queue snapshot once (consistent
       across the whole pass).
    2. For each active pursuit, calls `Observations.refresh!/3` to update
       persistent stall / zero-seeder timestamps.
    3. Builds a `Snapshot` over the refreshed pursuit, runs `Policy`, and
       dispatches the resulting `Action` to the corresponding command.

  The Watcher contains zero domain logic — every action is exercised by
  either a `Policy` test (deciding) or a `Commands.*Test` (executing);
  `WatcherTest` asserts dispatch wiring only.
  """

  use Oban.Worker, queue: :acquisition

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Observations, Policy, Snapshots}

  alias MediaCentarr.Acquisition.Pursuits.Commands.{
    AutoCancel,
    Exhaust,
    RequestDecision
  }

  alias MediaCentarr.Acquisition.QueueMonitor

  @impl Oban.Worker
  def perform(_job) do
    queue = read_queue_state()
    now = DateTime.utc_now(:second)

    Enum.each(Pursuits.list_active(), fn pursuit ->
      refreshed = Observations.refresh!(pursuit, queue, now)

      refreshed
      |> Snapshots.build()
      |> Policy.evaluate()
      |> dispatch(refreshed)
    end)

    :ok
  end

  defp dispatch(:no_action, _pursuit), do: :ok

  defp dispatch({:auto_cancel, reason}, pursuit) do
    Log.info(
      :acquisition,
      "pursuit watcher dispatch — auto_cancel (#{reason}) — #{pursuit.title}"
    )

    AutoCancel.execute(%{pursuit_id: pursuit.id, reason: reason})
  end

  defp dispatch({:request_decision, prompt}, pursuit) do
    Log.info(
      :acquisition,
      "pursuit watcher dispatch — request_decision — #{pursuit.title}"
    )

    RequestDecision.execute(%{pursuit_id: pursuit.id, prompt: prompt})
  end

  defp dispatch({:exhaust, reason}, pursuit) do
    Log.info(:acquisition, "pursuit watcher dispatch — exhaust (#{reason}) — #{pursuit.title}")
    Exhaust.execute(%{pursuit_id: pursuit.id, reason: reason})
  end

  defp read_queue_state do
    QueueMonitor.snapshot()
  rescue
    _ -> :unknown
  end
end
