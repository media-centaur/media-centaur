defmodule MediaCentarr.Acquisition.Pursuits.Commands.PickTarget do
  @moduledoc """
  Records the user's chosen release as the new target — used by both
  the decision card ("Pick this") and the manual-search submit flow.

  Replaces v0.54/0.55's `RecordUserChoice` command, and unifies it
  with the manual-grab target-creation that previously lived inline
  in `Acquisition.grab/2`.

  Caller is responsible for the Prowlarr HTTP submit (`Prowlarr.grab/1`)
  *before* invoking this command — atomicity is bounded to the pursuit
  + target rows + events.

  ## Side effects

  Inside one Repo transaction:

  1. Mark the previous `current_target` as `failed`
     (reason `"replaced_by_pick"`) if it isn't already terminal.
  2. Insert a new target in `acquired` carrying the picked release's
     guid / title / quality.
  3. Update `pursuit.current_target_id` to the new target.
  4. Bump `pursuit.attempt_count` and append the picked guid to
     `tried_release_guids` (so a subsequent `ChangeTarget` won't
     re-suggest the same release).
  5. Clear `pursuit.awaiting_decision_at` (the user just picked).
  6. Record `user_decision_recorded` + `fallback_initiated` events.
  """

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.{FallbackInitiated, UserDecisionRecorded}
  alias MediaCentarr.Acquisition.SearchResult
  alias MediaCentarr.Acquisition.{Target, TargetStatus}
  alias MediaCentarr.Repo

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

    log_label = fn pursuit ->
      "pursuit target picked — #{pursuit.title} — #{label}"
    end

    Runner.run(id, log_label, fn pursuit ->
      previous_guid = List.last(pursuit.tried_release_guids || [])
      now = DateTime.utc_now(:second)

      with {:ok, _previous_target} <- maybe_fail_current_target(pursuit),
           {:ok, new_target} <- insert_acquired_target(pursuit, result, origin),
           {:ok, attempted} <-
             Repo.update(Pursuit.record_attempt_changeset(pursuit, result.guid)),
           {:ok, with_target} <-
             Repo.update(Pursuit.set_current_target_changeset(attempted, new_target.id)),
           {:ok, resumed} <-
             Repo.update(Pursuit.clear_awaiting_decision_changeset(with_target)),
           {:ok, _decision_event} <-
             Events.record(%UserDecisionRecorded{
               pursuit_id: resumed.id,
               pursuit_title: resumed.title,
               occurred_at: now,
               choice: label
             }),
           {:ok, _fallback_event} <-
             Events.record(%FallbackInitiated{
               pursuit_id: resumed.id,
               pursuit_title: resumed.title,
               occurred_at: now,
               previous_guid: previous_guid,
               reason: "user_choice"
             }) do
        {:ok, resumed}
      end
    end)
  end

  defp maybe_fail_current_target(%Pursuit{current_target_id: nil}), do: {:ok, nil}

  defp maybe_fail_current_target(%Pursuit{current_target_id: target_id}) do
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

  defp insert_acquired_target(%Pursuit{} = pursuit, %SearchResult{} = result, origin) do
    result
    |> Target.acquired_changeset(pursuit_id: pursuit.id, origin: origin)
    |> Repo.insert()
  end
end
