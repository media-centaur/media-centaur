defmodule MediaCentaur.Acquisition.Pursuits.Commands.RequestDecision do
  @moduledoc "Sets a unit's awaiting-decision flag and records the prompt."

  alias MediaCentaur.Acquisition.Pursuits.Commands.Runner
  alias MediaCentaur.Acquisition.Pursuits.Events
  alias MediaCentaur.Acquisition.Pursuits.Events.UserDecisionRequested
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit, Units}
  alias MediaCentaur.Repo

  @doc """
  Sets `awaiting_decision_at` on the pursuit's unit and records a
  `user_decision_requested` event with the prompt. Lifecycle states are
  unchanged — the unit is still `active`, just blocked on user input.
  Alternatives are fetched just-in-time when the user opens the
  decision card.

  Accepts an optional `:unit_id`; without one the unit resolves via
  `Units.single!/1` (every pursuit is single-unit until the batch-grab
  collapse lands — ADR-055).

  Idempotent: re-issuing the command on a unit that already has
  `awaiting_decision_at` set is a no-op and returns `{:ok, pursuit}`.
  This lets the `PursueTarget` worker call this safely on every wake
  without having to itself track whether the unit is already awaiting
  a user pick.
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def execute(%{pursuit_id: id, prompt: prompt} = args) when is_binary(prompt) do
    label = fn pursuit -> "pursuit awaiting decision — #{pursuit.title} — #{prompt}" end
    now = DateTime.utc_now(:second)

    Runner.run(id, label, fn pursuit ->
      case resolve_unit(pursuit, args) do
        %Unit{awaiting_decision_at: %DateTime{}} ->
          {:ok, pursuit}

        %Unit{} = unit ->
          with {:ok, _updated} <-
                 Repo.update(Unit.set_awaiting_decision_changeset(unit, now)),
               {:ok, _event} <-
                 Events.record(%UserDecisionRequested{
                   pursuit_id: pursuit.id,
                   pursuit_title: pursuit.title,
                   occurred_at: now,
                   prompt: prompt
                 }) do
            {:ok, pursuit}
          end
      end
    end)
  end

  defp resolve_unit(_pursuit, %{unit_id: unit_id}) when is_binary(unit_id) do
    {:ok, unit} = Units.get(unit_id)
    unit
  end

  defp resolve_unit(pursuit, _args), do: Units.single!(pursuit.id)
end
