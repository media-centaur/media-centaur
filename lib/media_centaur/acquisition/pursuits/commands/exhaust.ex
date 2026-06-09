defmodule MediaCentaur.Acquisition.Pursuits.Commands.Exhaust do
  @moduledoc """
  Exhausts a pursuit's unit at give-up time and refolds the parent
  (ADR-055). When the refold lands the pursuit terminal, cancels every
  in-flight target so snoozed `PursueTarget` Oban jobs early-exit on
  their next wake, and records the `pursuit_exhausted` event.
  """

  alias MediaCentaur.Acquisition.Pursuits.Commands.{Refold, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.PursuitExhausted
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State, Unit, Units}
  alias MediaCentaur.Acquisition.Targets
  alias MediaCentaur.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, reason: reason} = args) when is_atom(reason) do
    Runner.run(id, "pursuit exhausted", fn pursuit ->
      unit = resolve_unit(pursuit, args)

      with true <- pursuit.state in State.in_flight() || {:error, :not_eligible},
           {:ok, exhausted_unit} <- Repo.update(Unit.exhaust_changeset(unit)),
           {:ok, refolded, _transition} <- Refold.refold!(pursuit),
           :ok <- maybe_close_and_record(refolded, exhausted_unit, reason) do
        {:ok, refolded}
      end
    end)
  end

  defp resolve_unit(_pursuit, %{unit_id: unit_id}) when is_binary(unit_id) do
    {:ok, unit} = Units.get(unit_id)
    unit
  end

  defp resolve_unit(pursuit, _args), do: Units.single!(pursuit.id)

  defp maybe_close_and_record(%Pursuit{} = pursuit, %Unit{} = unit, reason) do
    if State.terminal?(pursuit.state) do
      :ok = Targets.close_in_flight_for(pursuit.id, nil, "pursuit_exhausted")

      case Events.record(%PursuitExhausted{
             pursuit_id: pursuit.id,
             pursuit_title: pursuit.title,
             occurred_at: DateTime.utc_now(:second),
             attempt_count: unit.attempt_count,
             reason: Atom.to_string(reason)
           }) do
        {:ok, _event} -> :ok
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end
end
