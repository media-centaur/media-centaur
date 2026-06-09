defmodule MediaCentaur.Acquisition.Pursuits.Commands.PickTarget do
  @moduledoc """
  Records the user's chosen release as the new target — used by both
  the decision card ("Pick this") and the manual-search submit flow.

  Replaces v0.54/0.55's `RecordUserChoice` command, and unifies it
  with the manual-grab target-creation that previously lived inline
  in `Acquisition.grab/2`.

  Caller is responsible for the Prowlarr HTTP submit (`Prowlarr.grab/1`)
  *before* invoking this command — atomicity is bounded to the unit
  + target rows + events.

  ## Side effects

  Inside one Repo transaction, on the pursuit's unit (`Units.single!/1`
  until unit-scoped args land — ADR-055):

  1. Mark the unit's previous `current_target` as `failed`
     (reason `"replaced_by_pick"`) if it isn't already terminal.
  2. Insert a new target in `acquired` carrying the picked release's
     guid / title / quality, covering the unit.
  3. Update `unit.current_target_id` to the new target.
  4. Bump `unit.attempt_count` and append the picked guid to
     `unit.tried_release_guids` (so a subsequent `ChangeTarget` won't
     re-suggest the same release).
  5. Clear `unit.awaiting_decision_at` (the user just picked).
  6. Record `user_decision_recorded` + `fallback_initiated` events.
  """

  alias MediaCentaur.Acquisition.Pursuits.Commands.Runner
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.{FallbackInitiated, UserDecisionRecorded}
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, TargetUnit, Unit, Units}
  alias MediaCentaur.Search.SearchResult
  alias MediaCentaur.Acquisition.{InfoHash, Target, TargetStatus}
  alias MediaCentaur.Repo

  @doc """
  Records the picked release on a pursuit.

  Required: `pursuit_id`, `result :: SearchResult.t()`, `choice_label :: String.t()`.
  Optional: `origin :: "auto" | "manual"` (defaults to `"manual"`).
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, result: %SearchResult{} = result, choice_label: label} = args)
      when is_binary(label) do
    origin = Map.get(args, :origin, "manual")
    torrent_hash = InfoHash.resolve(result)

    log_label = fn pursuit ->
      "pursuit target picked — #{pursuit.title} — #{label}"
    end

    Runner.run(id, log_label, fn pursuit ->
      # Awaiting-or-lead: a pick from the decision card lands on the
      # unit that asked for it (Units.lead_of/1 prefers the awaiting
      # unit); per-unit drill-down lands with Phase 1c.
      unit = Units.lead(pursuit.id)
      previous_guid = List.last(unit.tried_release_guids || [])
      now = DateTime.utc_now(:second)

      with {:ok, _previous_target} <- maybe_fail_current_target(unit),
           {:ok, new_target} <- insert_acquired_target(pursuit, result, origin, torrent_hash),
           {:ok, _coverage} <-
             Repo.insert(TargetUnit.create_changeset(%{target_id: new_target.id, unit_id: unit.id})),
           {:ok, attempted} <-
             Repo.update(Unit.record_attempt_changeset(unit, result.guid)),
           {:ok, with_target} <-
             Repo.update(Unit.set_current_target_changeset(attempted, new_target.id)),
           {:ok, _resumed} <-
             Repo.update(Unit.clear_awaiting_decision_changeset(with_target)),
           {:ok, _decision_event} <-
             Events.record(%UserDecisionRecorded{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: now,
               choice: label
             }),
           {:ok, _fallback_event} <-
             Events.record(%FallbackInitiated{
               pursuit_id: pursuit.id,
               pursuit_title: pursuit.title,
               occurred_at: now,
               previous_guid: previous_guid,
               reason: "user_choice"
             }) do
        {:ok, pursuit}
      end
    end)
  end

  defp maybe_fail_current_target(%Unit{current_target_id: nil}), do: {:ok, nil}

  defp maybe_fail_current_target(%Unit{current_target_id: target_id}) do
    case Repo.get(Target, target_id) do
      nil ->
        {:ok, nil}

      %Target{status: status} = target ->
        if TargetStatus.terminal?(status) do
          {:ok, target}
        else
          target
          |> Target.failed_changeset("replaced_by_pick")
          |> Repo.update()
        end
    end
  end

  defp insert_acquired_target(%Pursuit{} = pursuit, %SearchResult{} = result, origin, torrent_hash) do
    result
    |> Target.acquired_changeset(pursuit_id: pursuit.id, origin: origin, torrent_hash: torrent_hash)
    |> Repo.insert()
  end
end
