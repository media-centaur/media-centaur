defmodule MediaCentarr.Acquisition.Pursuits.Commands.Satisfy do
  @moduledoc """
  Closes a pursuit on verified arrival.

  At terminal-pursuit transition, the command also closes out every
  in-flight target row on the pursuit: the `final_target_id` (the
  target whose release actually landed) is promoted to `succeeded`,
  and every other `seeking`/`acquired` sibling is cancelled with
  reason `"pursuit_satisfied"`. This is what prevents a snoozed
  `PursueTarget` Oban job from waking hours later and grabbing a
  duplicate release on a pursuit that's already done.
  """

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitSatisfied
  alias MediaCentarr.Acquisition.Targets
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, final_target_id: target_id, final_release_title: title}) do
    Runner.run(id, "pursuit satisfied", fn pursuit ->
      with {:ok, updated} <- Repo.update(Pursuit.satisfy_changeset(pursuit)),
           :ok <- Targets.close_in_flight_for(updated.id, target_id, "pursuit_satisfied"),
           {:ok, _event} <-
             Events.record(%PursuitSatisfied{
               pursuit_id: updated.id,
               pursuit_title: updated.title,
               occurred_at: DateTime.utc_now(:second),
               final_target_id: target_id,
               final_release_title: title
             }) do
        {:ok, updated}
      end
    end)
  end
end
