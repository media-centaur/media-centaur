defmodule MediaCentaur.Acquisition.Pursuits.Watcher do
  @moduledoc """
  Periodic orchestrator driving Policy for every active unit (ADR-055).

  Each tick:

    1. Reads the current download-client queue snapshot once (consistent
       across the whole pass).
    2. For each active pursuit, calls `Observations.observe_pursuit!/4`
       once to record torrent lifecycle transitions on the timeline.
    3. For each active unit, calls `Observations.refresh!/5` to update
       the unit's persistent stall / zero-seeder timestamps.
    4. Builds a `Snapshot` over the refreshed unit, runs `Policy`, and
       dispatches the resulting `Action` to the corresponding command.

  The Watcher contains zero domain logic — every action is exercised by
  either a `Policy` test (deciding) or a `Commands.*Test` (executing);
  `WatcherTest` asserts dispatch wiring only.
  """

  use Oban.Worker, queue: :acquisition

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Corpus
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

    # Lifecycle observation runs once per PURSUIT — the tracked torrent
    # is shared by all of a composite pursuit's units, so observing it
    # in the per-unit loop multiplied every timeline event by the unit
    # count (38 identical "Download started" rows for a 38-episode
    # season pack).
    observed_pursuits =
      triples
      |> Enum.map(fn {pursuit, _unit, _target} -> pursuit end)
      |> Enum.uniq_by(& &1.id)
      |> Map.new(fn pursuit ->
        release_title = Map.get(release_titles, pursuit.id)
        {pursuit.id, Observations.observe_pursuit!(pursuit, queue, now, release_title)}
      end)

    Enum.each(triples, fn {pursuit, unit, current_target} ->
      pursuit = Map.fetch!(observed_pursuits, pursuit.id)
      release_title = Map.get(release_titles, pursuit.id)
      refreshed = Observations.refresh!(pursuit, unit, queue, now, release_title)

      # First-observation capture of the download's durable file link onto
      # the current target (write-once); later resolves the lifecycle stage.
      DownloadIdentity.capture!(current_target, queue, release_title)

      snapshot = Snapshots.build(pursuit, refreshed, queue, current_target)
      dispatch(Policy.evaluate(snapshot), pursuit, refreshed, snapshot)
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
