defmodule MediaCentaur.Acquisition.Pursuits.Commands.Refold do
  @moduledoc """
  Transaction helper that re-derives a composite pursuit's state from
  its unit states (ADR-055).

  Not a public command — unit-transitioning commands call `refold!/1`
  inside their `Runner` transaction after changing a unit, so the
  parent row and its units can never drift. The fold itself is pure
  (`State.fold_units/1`); this module only loads the unit states and
  applies the change.

  Returns `{:ok, pursuit, transition}` where `transition` is
  `:unchanged` or `{:changed, previous_state}` — callers use it to
  decide whether a parent-level lifecycle event should be recorded.
  """

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State, Units}
  alias MediaCentaur.Repo

  @spec refold!(Pursuit.t()) ::
          {:ok, Pursuit.t(), :unchanged | {:changed, String.t()}} | {:error, Ecto.Changeset.t()}
  def refold!(%Pursuit{} = pursuit) do
    folded = pursuit.id |> Units.states_for() |> State.fold_units()

    if folded == pursuit.state do
      {:ok, pursuit, :unchanged}
    else
      case Repo.update(Pursuit.fold_changeset(pursuit, folded)) do
        {:ok, updated} -> {:ok, updated, {:changed, pursuit.state}}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end
end
