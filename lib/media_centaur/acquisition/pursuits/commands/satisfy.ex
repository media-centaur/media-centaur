defmodule MediaCentaur.Acquisition.Pursuits.Commands.Satisfy do
  @moduledoc """
  Satisfies the unit(s) covered by a landed release and refolds the
  parent pursuit (ADR-055).

  The units to satisfy are resolved from `final_target_id`'s coverage
  (`Units.covered_by/1`) — the target whose release actually landed.
  When coverage is missing (legacy rows), falls back to the pursuit's
  sole unit.

  When the refold lands the pursuit in a terminal state, the command
  also closes out every in-flight target row on the pursuit: the
  `final_target_id` is promoted to `succeeded`, and every other
  `seeking`/`acquired` sibling is cancelled with reason
  `"pursuit_satisfied"`. This is what prevents a snoozed
  `PursueTarget` Oban job from waking hours later and grabbing a
  duplicate release on a pursuit that's already done. A
  `pursuit_satisfied` event records the terminal transition.
  """

  alias MediaCentaur.Acquisition.Pursuits.Commands.{Refold, Runner}
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.PursuitSatisfied
  alias MediaCentaur.Acquisition.Pursuits.{State, Unit, UnitState, Units}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Targets
  alias MediaCentaur.Acquisition.TrackingHandoffs
  alias MediaCentaur.Repo

  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, final_target_id: target_id, final_release_title: title}) do
    result =
      Runner.run(id, "pursuit satisfied", fn pursuit ->
        # Terminal pursuits don't re-satisfy — without this guard a second
        # call would record a duplicate pursuit_satisfied event.
        with true <- pursuit.state in State.in_flight() || {:error, :not_eligible},
             {:ok, _units} <- satisfy_covered_units(pursuit, target_id),
             {:ok, refolded, _transition} <- Refold.refold!(pursuit),
             :ok <- maybe_close_and_record(refolded, target_id, title) do
          {:ok, refolded}
        end
      end)

    # Post-transaction by design: the grab-future handoff fetches TMDB
    # when it fires, which must never run inside the Runner's
    # transaction nor fail the satisfy.
    with {:ok, pursuit} <- result do
      TrackingHandoffs.maybe_grab_future(pursuit)
    end

    result
  end

  defp satisfy_covered_units(pursuit, target_id) do
    pursuit
    |> units_to_satisfy(target_id)
    |> Enum.reject(&UnitState.terminal?(&1.state))
    |> Enum.reduce_while({:ok, []}, fn unit, {:ok, satisfied} ->
      case Repo.update(Unit.satisfy_changeset(unit)) do
        {:ok, updated} -> {:cont, {:ok, [updated | satisfied]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp units_to_satisfy(pursuit, target_id) do
    case target_id && Units.covered_by(target_id) do
      covered when is_list(covered) and covered != [] -> covered
      _ -> Units.for_pursuit(pursuit.id)
    end
  end

  defp maybe_close_and_record(%Pursuit{} = pursuit, target_id, title) do
    if State.terminal?(pursuit.state) do
      :ok = Targets.close_in_flight_for(pursuit.id, target_id, "pursuit_satisfied")

      case Events.record(%PursuitSatisfied{
             pursuit_id: pursuit.id,
             pursuit_title: pursuit.title,
             occurred_at: DateTime.utc_now(:second),
             final_target_id: target_id,
             final_release_title: title
           }) do
        {:ok, _event} -> :ok
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end
end
