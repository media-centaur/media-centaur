defmodule MediaCentaur.Acquisition.Pursuits.Commands.Cancel do
  @moduledoc """
  Closes a pursuit by user request — cancels every still-active unit
  and refolds the parent (ADR-055; a pursuit with satisfied units
  folds to `partial`, one with none folds to `cancelled`). Cancels
  every in-flight target so snoozed `PursueTarget` Oban jobs
  early-exit on their next wake, and records the `pursuit_cancelled`
  event.
  """

  alias MediaCentaur.Acquisition.Pursuits.Commands.{Refold, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.PursuitCancelled
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State, Unit, Units}
  alias MediaCentaur.Acquisition.Targets
  alias MediaCentaur.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, cancelled_by: by, reason: reason})
      when is_atom(by) and is_binary(reason) do
    Runner.run(id, "pursuit cancelled", fn pursuit ->
      with true <- pursuit.state in State.in_flight() || {:error, :not_eligible},
           {:ok, _units} <- cancel_active_units(pursuit),
           {:ok, refolded, _transition} <- Refold.refold!(pursuit),
           :ok <- Targets.close_in_flight_for(refolded.id, nil, "pursuit_cancelled"),
           {:ok, _event} <-
             Events.record(%PursuitCancelled{
               pursuit_id: refolded.id,
               pursuit_title: refolded.title,
               occurred_at: DateTime.utc_now(:second),
               cancelled_by: Atom.to_string(by),
               reason: reason
             }) do
        {:ok, refolded}
      end
    end)
  end

  defp cancel_active_units(pursuit) do
    pursuit.id
    |> Units.active_for()
    |> Enum.reduce_while({:ok, []}, fn unit, {:ok, cancelled} ->
      case Repo.update(Unit.cancel_changeset(unit)) do
        {:ok, updated} -> {:cont, {:ok, [updated | cancelled]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
