defmodule MediaCentaur.Acquisition.Pursuits.Watcher do
  @moduledoc """
  Periodic orchestrator driving Policy for every active unit (ADR-055).

  Each tick:

    1. Reads the current download-client queue snapshot once (consistent
       across the whole pass).
    2. For each active unit, builds a `Snapshot` and runs `Policy`, then
       dispatches the resulting `Action` to the corresponding command.
    3. Reconciles pursuits whose file already landed, and prunes the corpus.

  It *decides*; it does not *observe*. Observation runs on the download
  client's clock in `Pursuits.QueueListener` — every 10–30 s rather than every
  15 minutes, because a download can start and finish between two ticks of
  this worker. `Policy`'s own windows are measured in hours, so this cadence
  is right for deciding and wrong for seeing.

  The Watcher contains zero domain logic — every action is exercised by
  either a `Policy` test (deciding) or a `Commands.*Test` (executing);
  `WatcherTest` asserts dispatch wiring only.
  """

  use Oban.Worker, queue: :acquisition

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.Pursuits

  alias MediaCentaur.Acquisition.Pursuits.{LibraryReconciler, Policy, Snapshots}

  alias MediaCentaur.Acquisition.Pursuits.Commands.{
    AutoCancel,
    Exhaust,
    RequestDecision
  }

  alias MediaCentaur.Downloads.QueueMonitor

  @impl Oban.Worker
  def perform(_job) do
    queue = read_queue_state()

    # Batch-fetch the three things every active unit needs:
    # (1) the pursuit + unit + its current_target, (2) the latest
    # release_title per pursuit. Reduces the per-tick DB cost to a
    # constant handful of queries regardless of how many units are in
    # flight.
    triples = Pursuits.list_active_units_with_context()

    Enum.each(triples, fn {pursuit, unit, current_target} ->
      snapshot = Snapshots.build(pursuit, unit, queue, current_target)
      dispatch(Policy.evaluate(snapshot), pursuit, unit, snapshot)
    end)

    # Safety-net for the PubSub-driven completion path — closes
    # pursuits whose file is already in the library but never got
    # picked up by `InboundListener` → `IdentityVerifier` → `Satisfy`.
    LibraryReconciler.reconcile_active()

    # Corpus retention (ADR-033 — delete over hide): searches and
    # candidates beyond the retention window are deleted each tick.
    Corpus.prune_stale!()

    :ok
  end

  defp dispatch(:no_action, _pursuit, _unit, _snapshot), do: :ok

  defp dispatch({:auto_cancel, reason}, pursuit, unit, snapshot) do
    Log.info(
      :acquisition,
      "pursuit watcher dispatch — auto_cancel (#{reason}) — #{pursuit.title}"
    )

    # `detail` is the client's own failure message (set for
    # :download_failed, nil otherwise) — recorded on the auto_cancelled
    # event so the timeline can say why the client gave up.
    AutoCancel.execute(%{
      pursuit_id: pursuit.id,
      unit_id: unit.id,
      reason: reason,
      detail: snapshot.download_failure_message
    })
  end

  defp dispatch({:request_decision, prompt}, pursuit, unit, _snapshot) do
    Log.info(
      :acquisition,
      "pursuit watcher dispatch — request_decision — #{pursuit.title}"
    )

    RequestDecision.execute(%{pursuit_id: pursuit.id, unit_id: unit.id, prompt: prompt})
  end

  defp dispatch({:exhaust, reason}, pursuit, unit, _snapshot) do
    Log.info(:acquisition, "pursuit watcher dispatch — exhaust (#{reason}) — #{pursuit.title}")
    Exhaust.execute(%{pursuit_id: pursuit.id, unit_id: unit.id, reason: reason})
  end

  defp read_queue_state do
    QueueMonitor.snapshot()
  rescue
    _ -> :unknown
  end
end
