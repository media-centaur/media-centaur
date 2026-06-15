defmodule MediaCentaur.Acquisition.Pursuits.Commands.AutoCancel do
  @moduledoc """
  Auto-pivots a pursuit's unit when a safe-case is confirmed
  (zero-seeders, irrecoverable error). Cancels the dead release and
  immediately starts a fresh search — the previous release's guid lands
  on the unit's `tried_release_guids` so the next attempt can't re-pick
  it.

  ## Why pivot, not just cancel

  Policy emits `{:auto_cancel, reason}` for safe cases (zero-seeders is
  the canonical example — the release is definitively dead). The unit's
  goal is unchanged, only this particular release attempt failed.
  Leaving the unit `active` with a cancelled `current_target` is the
  precise failure mode pursuits were built to prevent: the user ends up
  with a dangling row that nothing else moves forward.

  Stall confirmations go through `RequestDecision` instead — those are
  taste cases where the user picks the alternative.

  ## Side effects

  Inside one Repo transaction, on the unit (`Units.single!/1` unless a
  `:unit_id` is given — ADR-055):

  1. Mark every in-flight target *covering this unit* as `cancelled`
     with the auto-cancel reason (typically just the unit's
     `current_target`).
  2. Bump `unit.attempt_count` and append the previous target's
     `prowlarr_guid` to `unit.tried_release_guids` (so the next search
     filters it out).
  3. Record `auto_cancelled` event.
  4. If a target was cancelled, insert a fresh `seeking` target covering
     the unit, update `unit.current_target_id`, and record a
     `target_changed` event.

  After the transaction commits, enqueue `Jobs.PursueTarget` for the
  new target. Unit and pursuit states remain `active` throughout — the
  goal is still chasing, just chasing a different release.

  When the unit has no current target (idle edge case), the command
  records `auto_cancelled` only — there's nothing to pivot to.
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits.Commands.{ClientCleanup, Helpers, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.{AutoCancelled, TargetChanged}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, TargetUnit, Unit, Units}
  alias MediaCentaur.Acquisition.{Target, Targets, TargetStatus}
  alias MediaCentaur.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason} = args) when is_atom(reason) do
    label = fn pursuit -> "pursuit auto-cancelled (#{reason}) — #{pursuit.title}" end
    now = DateTime.utc_now(:second)

    result =
      Runner.run(id, label, fn pursuit ->
        unit = resolve_unit(pursuit, args)
        # Hashes of the downloads this pivot abandons — read before the
        # status flip; removed from the client post-commit.
        abandoned_hashes = Targets.in_flight_hashes_for_unit(unit.id)
        prior_guid = previous_target_guid(unit)
        cancel_in_flight_targets(unit, reason, now)

        with {:ok, attempted_unit} <-
               Repo.update(Unit.record_attempt_changeset(unit, prior_guid)),
             {:ok, _auto_cancelled} <-
               Events.record(%AutoCancelled{
                 pursuit_id: pursuit.id,
                 pursuit_title: pursuit.title,
                 occurred_at: now,
                 reason: Atom.to_string(reason)
               }) do
          with {:ok, {pivoted, new_target}} <-
                 pivot_if_had_target(pursuit, attempted_unit, unit, now) do
            {:ok, {pivoted, new_target, abandoned_hashes}}
          end
        end
      end)

    case result do
      {:ok, {pivoted, %Target{} = new_target, abandoned_hashes}} ->
        Helpers.enqueue_pursue(new_target)
        ClientCleanup.stop_downloads(pivoted.title, abandoned_hashes)
        {:ok, pivoted}

      {:ok, {pivoted, nil, abandoned_hashes}} ->
        ClientCleanup.stop_downloads(pivoted.title, abandoned_hashes)
        {:ok, pivoted}

      other ->
        other
    end
  end

  defp resolve_unit(_pursuit, %{unit_id: unit_id}) when is_binary(unit_id) do
    {:ok, unit} = Units.get(unit_id)
    unit
  end

  # Auto-cancel without an explicit unit only makes sense for a single-unit
  # pursuit; single!/1 raises on a composite (ADR-055) to flag a call site
  # that still needs a unit-scoped argument. (ChangeTarget differs — it
  # pivots a composite's lead unit via lead/1.)
  defp resolve_unit(pursuit, _args), do: Units.single!(pursuit.id)

  defp previous_target_guid(%Unit{current_target_id: nil}), do: nil

  defp previous_target_guid(%Unit{current_target_id: id}) do
    case Repo.get(Target, id) do
      %Target{prowlarr_guid: guid} -> guid
      _ -> nil
    end
  end

  # Cancels in-flight targets covering THIS unit only — sibling units'
  # downloads are untouched (ADR-055).
  defp cancel_in_flight_targets(%Unit{} = unit, reason, now) do
    covering = from(tu in TargetUnit, where: tu.unit_id == ^unit.id, select: tu.target_id)

    Target
    |> where([t], t.id in subquery(covering) and t.status in ^TargetStatus.cancellable())
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

  # Only pivot when the unit had a current target — idle units
  # (current_target_id == nil) have nothing to pivot to.
  defp pivot_if_had_target(pursuit, _attempted_unit, %Unit{current_target_id: nil}, _now),
    do: {:ok, {pursuit, nil}}

  defp pivot_if_had_target(pursuit, attempted_unit, _original_unit, now) do
    with {:ok, new_target} <- Helpers.insert_seeking_target(pursuit),
         {:ok, _coverage} <-
           Repo.insert(
             TargetUnit.create_changeset(%{target_id: new_target.id, unit_id: attempted_unit.id})
           ),
         {:ok, _updated_unit} <-
           Repo.update(Unit.set_current_target_changeset(attempted_unit, new_target.id)),
         {:ok, _event} <-
           Events.record(%TargetChanged{
             pursuit_id: pursuit.id,
             pursuit_title: pursuit.title,
             occurred_at: now,
             target_id: new_target.id
           }) do
      {:ok, {pursuit, new_target}}
    end
  end
end
