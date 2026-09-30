defmodule MediaCentaur.Acquisition.Jobs.GrabTarget do
  @moduledoc """
  Hands a `grabbing` target's chosen release to Prowlarr (campaign
  durable-work, G1). The target — and this job — are written together by
  `Targets.start_grabbing/4` when a person, a plan or the search chooses a
  release, so the choice is recorded before the grab and is never lost
  with a page or a task.

  On each run the target is re-read, and the job acts only while it is
  still `grabbing`:

    * **Prowlarr unconfigured or down** — no request; snooze (an hour, or
      the probe cadence), as `PursueTarget` and `RunPlan` do.
    * **The download client refuses the hand-off** (known beforehand from
      availability, or from the grab's answer) — an outage, not a bad
      release: recorded on the target (`Targets.record_hold/3`) and snoozed
      at the probe cadence.
    * **Accepted** — the infohash is resolved and the target moves to
      `acquired`, exactly as `PursueTarget` lands its own grab.
    * **Refused** — the release is the problem: the target fails
      (`grab_refused`), each unit it covered records the release as tried,
      and each gets a new seeking target (`Targets.seek_again/2`).

  A crash after Prowlarr accepted the grab and before the target is
  written re-grabs on retry. The grab is at-least-once; nothing here
  claims otherwise.
  """

  # Unique among grabs that have not started (ADR-077, rule 6).
  use Oban.Worker,
    queue: :acquisition,
    unique: [period: :infinity, keys: [:target_id], states: [:available, :scheduled, :retryable]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{CancelReasons, InfoHash, Target, TargetEvents, Targets}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit, Units}
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{ProbeJob, Prowlarr, Quality, SearchResult}

  @handoff_slots IntegrationAvailability.handoff_slots()
  # An unconfigured Prowlarr fails every request instantly; nothing to do
  # until Settings change (matches `PursueTarget`).
  @unconfigured_snooze_seconds 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"target_id" => target_id}}) do
    case Repo.get(Target, target_id) do
      %Target{status: "grabbing"} = target -> grab(target, Target.chosen_release(target))
      _gone_or_moved_on -> :ok
    end
  end

  defp grab(target, release) do
    cond do
      not Capabilities.prowlarr_ready?() -> {:snooze, @unconfigured_snooze_seconds}
      not IntegrationAvailability.up?(:prowlarr) -> {:snooze, ProbeJob.cadence_seconds()}
      handoff_down?(release) -> hold(target)
      true -> hand_off(target, release)
    end
  end

  defp handoff_down?(%SearchResult{protocol: protocol}) when protocol in @handoff_slots,
    do: not IntegrationAvailability.up?({:handoff, protocol})

  defp handoff_down?(%SearchResult{}), do: false

  defp hand_off(target, release) do
    case Prowlarr.grab(release) do
      :ok ->
        land(target, release)

      {:error, reason} ->
        if Prowlarr.grab_outage?(reason), do: hold(target), else: refuse(target, reason)
    end
  end

  defp hold(target) do
    cadence = ProbeJob.cadence_seconds()
    {:ok, _held} = Targets.record_hold(target, "download_client_unavailable", cadence)
    {:snooze, cadence}
  end

  defp land(target, release) do
    quality = Quality.label(release.quality)

    {:ok, acquired} =
      target
      |> Target.acquire_changeset(quality, release.title, release.guid, InfoHash.resolve(release))
      |> Repo.update()

    Acquisition.broadcast_update(%TargetEvents.Acquired{target: acquired})
    # The client has just been handed the release: refresh the queue
    # snapshot rather than showing "Grabbed" for a whole poll cadence.
    QueueMonitor.poll_now()
    Log.info(:acquisition, "grab accepted #{quality} — #{target.title}")
    :ok
  end

  defp refuse(target, reason) do
    pursuit = Repo.get!(Pursuit, target.pursuit_id)

    {:ok, failed} =
      Repo.transaction(fn ->
        {:ok, failed} = Repo.update(Target.failed_changeset(target, CancelReasons.grab_refused()))

        # The refused release counts as an attempt and is not tried again
        # by the search that follows.
        units =
          Enum.map(Units.covered_by(target.id), fn unit ->
            {:ok, attempted} = Repo.update(Unit.record_attempt_changeset(unit, target.prowlarr_guid))
            attempted
          end)

        :ok = Targets.seek_again(pursuit, units)
        failed
      end)

    Acquisition.broadcast_update(%TargetEvents.Failed{target: failed})

    Log.warning(
      :acquisition,
      "grab refused — #{target.release_title} — #{inspect(reason)}; searching again for #{target.title}"
    )

    :ok
  end
end
