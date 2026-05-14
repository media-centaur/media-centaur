defmodule MediaCentarr.Acquisition.Pursuits.Commands.Exhaust do
  @moduledoc """
  Closes a pursuit at give-up time. Cancels every in-flight target so
  snoozed `PursueTarget` Oban jobs early-exit on their next wake.
  """

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Runner
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitExhausted
  alias MediaCentarr.Acquisition.Targets
  alias MediaCentarr.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason}) when is_atom(reason) do
    Runner.run(id, "pursuit exhausted", fn pursuit ->
      with {:ok, updated} <- Repo.update(Pursuit.exhaust_changeset(pursuit)),
           :ok <- Targets.close_in_flight_for(updated.id, nil, "pursuit_exhausted"),
           {:ok, _event} <-
             Events.record(%PursuitExhausted{
               pursuit_id: updated.id,
               pursuit_title: updated.title,
               occurred_at: DateTime.utc_now(:second),
               attempt_count: updated.attempt_count,
               reason: Atom.to_string(reason)
             }) do
        {:ok, updated}
      end
    end)
  end
end
