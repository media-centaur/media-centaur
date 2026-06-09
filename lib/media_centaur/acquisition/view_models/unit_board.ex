defmodule MediaCentaur.Acquisition.ViewModels.UnitBoard do
  @moduledoc """
  Display contract for the per-unit drill-down of a composite pursuit
  (ADR-055) — the embryo of the media-search campaign's coverage board.

  One row per unit: what the unit wants (its label/term), where its
  thread stands (state + awaiting flag), and which release currently
  covers it. Built by `MediaCentaur.Acquisition.Pursuits.unit_board_for/1`;
  the modal renders it only for multi-unit pursuits (`wanted > 1`) —
  a single-unit pursuit's thread is already the whole modal.
  """

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard.Row

  @enforce_keys [:pursuit_id, :wanted, :satisfied, :units]
  defstruct [:pursuit_id, :wanted, :satisfied, :units]

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          wanted: pos_integer(),
          satisfied: non_neg_integer(),
          units: [Row.t()]
        }

  defmodule Row do
    @moduledoc """
    One unit of the board: identity (`label` — the expanded term for
    query-door units, falling back to the pursuit title), thread state,
    and the release its current target carries. `actionable?` gates the
    per-unit "Change target" affordance — only in-flight units that are
    not already awaiting a user decision can pivot.
    """

    @enforce_keys [:id, :label, :state]
    defstruct [
      :id,
      :label,
      :state,
      :release_title,
      awaiting_decision?: false,
      actionable?: false
    ]

    @type state :: :active | :satisfied | :exhausted | :cancelled

    @type t :: %__MODULE__{
            id: Ecto.UUID.t(),
            label: String.t(),
            state: state(),
            release_title: String.t() | nil,
            awaiting_decision?: boolean(),
            actionable?: boolean()
          }
  end
end
