defmodule MediaCentarr.Acquisition.Pursuits.Commands.AutoCancel do
  @moduledoc """
  Auto-pivots a pursuit when a safe-case is confirmed (zero-seeders,
  irrecoverable error). Cancels the dead release and immediately starts
  a fresh search — the previous release's guid lands on
  `tried_release_guids` so the next attempt can't re-pick it.

  ## Why pivot, not just cancel

  Policy emits `{:auto_cancel, reason}` for safe cases (zero-seeders is
  the canonical example — the release is definitively dead). The
  pursuit's goal is unchanged, only this particular release attempt
  failed. Leaving the pursuit `active` with a cancelled `current_target`
  is the precise failure mode pursuits were built to prevent: the user
  ends up with a dangling row that nothing else moves forward.

  Stall confirmations go through `RequestDecision` instead — those are
  taste cases where the user picks the alternative.

  ## Side effects

  Inside one Repo transaction:

  1. Mark every in-flight target on the pursuit as `cancelled` with
     the auto-cancel reason (typically just the `current_target`, but
     `Repo.update_all` is uniform).
  2. Bump `pursuit.attempt_count` and append the previous target's
     `prowlarr_guid` to `tried_release_guids` (so the next search
     filters it out).
  3. Record `auto_cancelled` event.
  4. If a target was cancelled, insert a fresh `seeking` target, update
     `pursuit.current_target_id`, and record `target_changed` event.

  After the transaction commits, enqueue `Jobs.PursueTarget` for the
  new target. Pursuit state remains `active` throughout — the goal is
  still chasing, just chasing a different release.

  When the pursuit has no current target (idle edge case), the command
  records `auto_cancelled` only — there's nothing to pivot to.
  """

  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Jobs.PursueTarget, as: PursueTargetWorker
  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.{AutoCancelled, TargetChanged}
  alias MediaCentarr.Acquisition.{Target, TargetStatus}
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason}) when is_atom(reason) do
    label = fn pursuit -> "pursuit auto-cancelled (#{reason}) — #{pursuit.title}" end
    now = DateTime.utc_now(:second)

    result =
      Runner.run(id, label, fn pursuit ->
        prior_guid = previous_target_guid(pursuit)
        cancel_in_flight_targets(pursuit, reason, now)

        with {:ok, attempted} <-
               Repo.update(Pursuit.record_attempt_changeset(pursuit, prior_guid)),
             {:ok, _auto_cancelled} <-
               Events.record(%AutoCancelled{
                 pursuit_id: attempted.id,
                 pursuit_title: attempted.title,
                 occurred_at: now,
                 reason: Atom.to_string(reason)
               }) do
          pivot_if_had_target(attempted, pursuit, now)
        end
      end)

    case result do
      {:ok, {pivoted, %Target{} = new_target}} ->
        enqueue_pursue(new_target)
        {:ok, pivoted}

      {:ok, {pivoted, nil}} ->
        {:ok, pivoted}

      other ->
        other
    end
  end

  defp previous_target_guid(%Pursuit{current_target_id: nil}), do: nil

  defp previous_target_guid(%Pursuit{current_target_id: id}) do
    case Repo.get(Target, id) do
      %Target{prowlarr_guid: guid} -> guid
      _ -> nil
    end
  end

  defp cancel_in_flight_targets(pursuit, reason, now) do
    Target
    |> where([t], t.pursuit_id == ^pursuit.id and t.status in ^TargetStatus.cancellable())
    |> Repo.update_all(
      set: [
        status: "cancelled",
        cancelled_at: now,
        cancelled_reason: Atom.to_string(reason),
        next_attempt_at: nil,
        updated_at: now
      ]
    )
  end

  # Only pivot when the pursuit had a current target — idle pursuits
  # (current_target_id == nil) have nothing to pivot to.
  defp pivot_if_had_target(attempted, %Pursuit{current_target_id: nil}, _now),
    do: {:ok, {attempted, nil}}

  defp pivot_if_had_target(attempted, _original, now) do
    with {:ok, new_target} <- insert_seeking_target(attempted),
         {:ok, updated} <-
           Repo.update(Pursuit.set_current_target_changeset(attempted, new_target.id)),
         {:ok, _event} <-
           Events.record(%TargetChanged{
             pursuit_id: updated.id,
             pursuit_title: updated.title,
             occurred_at: now,
             target_id: new_target.id
           }) do
      {:ok, {updated, new_target}}
    end
  end

  defp insert_seeking_target(%Pursuit{} = pursuit) do
    %{pursuit_id: pursuit.id, title: pursuit.title, origin: pursuit.origin}
    |> Target.create_changeset()
    |> Repo.insert()
  end

  defp enqueue_pursue(%Target{} = target) do
    case Oban.insert(PursueTargetWorker.new(%{"target_id" => target.id})) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Log.warning(:acquisition, "PursueTarget enqueue failed — #{inspect(reason)}")
        :ok
    end
  end
end
