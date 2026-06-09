defmodule MediaCentaur.Acquisition.Pursuits.Watcher do
  @moduledoc """
  Periodic orchestrator driving Policy for every active unit (ADR-055).

  Each tick:

    1. Reads the current download-client queue snapshot once (consistent
       across the whole pass).
    2. For each active unit, calls `Observations.refresh!/5` to update
       the unit's persistent stall / zero-seeder timestamps.
    3. Builds a `Snapshot` over the refreshed unit, runs `Policy`, and
       dispatches the resulting `Action` to the corresponding command.

  The Watcher contains zero domain logic — every action is exercised by
  either a `Policy` test (deciding) or a `Commands.*Test` (executing);
  `WatcherTest` asserts dispatch wiring only.
  """

  use Oban.Worker, queue: :acquisition

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits

  alias MediaCentaur.Acquisition.Pursuits.{
    DownloadIdentity,
    LibraryReconciler,
    Observations,
    Policy,
    Snapshots
  }

  alias MediaCentaur.Acquisition.Pursuits.Commands.{
    AutoCancel,
    Exhaust,
    RequestDecision
  }

  alias MediaCentaur.Downloads.QueueMonitor

  @impl Oban.Worker
  def perform(_job) do
    queue = read_queue_state()
    now = DateTime.utc_now(:second)

    # Batch-fetch the three things every active unit needs:
    # (1) the pursuit + unit + its current_target, (2) the latest
    # release_title per pursuit. Reduces the per-tick DB cost to a
    # constant handful of queries regardless of how many units are in
    # flight.
    triples = Pursuits.list_active_units_with_context()
    pursuit_ids = triples |> Enum.map(fn {pursuit, _unit, _target} -> pursuit.id end) |> Enum.uniq()
    release_titles = Pursuits.latest_release_titles_for(pursuit_ids)

    Enum.each(triples, fn {pursuit, unit, current_target} ->
      release_title = Map.get(release_titles, pursuit.id)
      refreshed = Observations.refresh!(pursuit, unit, queue, now, release_title)

      # First-observation capture of the download's durable file link onto
      # the current target (write-once); later resolves the lifecycle stage.
      DownloadIdentity.capture!(current_target, queue, release_title)

      pursuit
      |> Snapshots.build(refreshed, queue, current_target)
      |> Policy.evaluate()
      |> dispatch(pursuit, refreshed)
    end)

    # Safety-net for the PubSub-driven completion path — closes
    # pursuits whose file is already in the library but never got
    # picked up by `InboundListener` → `IdentityVerifier` → `Satisfy`.
    LibraryReconciler.reconcile_active()

    :ok
  end

  defp dispatch(:no_action, _pursuit, _unit), do: :ok

  defp dispatch({:auto_cancel, reason}, pursuit, unit) do
    Log.info(
      :acquisition,
      "pursuit watcher dispatch — auto_cancel (#{reason}) — #{pursuit.title}"
    )

    AutoCancel.execute(%{pursuit_id: pursuit.id, unit_id: unit.id, reason: reason})
  end

  defp dispatch({:request_decision, prompt}, pursuit, unit) do
    Log.info(
      :acquisition,
      "pursuit watcher dispatch — request_decision — #{pursuit.title}"
    )

    RequestDecision.execute(%{pursuit_id: pursuit.id, unit_id: unit.id, prompt: prompt})
  end

  defp dispatch({:exhaust, reason}, pursuit, unit) do
    Log.info(:acquisition, "pursuit watcher dispatch — exhaust (#{reason}) — #{pursuit.title}")
    Exhaust.execute(%{pursuit_id: pursuit.id, unit_id: unit.id, reason: reason})
  end

  defp read_queue_state do
    QueueMonitor.snapshot()
  rescue
    _ -> :unknown
  end
end
