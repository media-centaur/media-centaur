defmodule MediaCentarr.Acquisition.ViewModels.PursuitHeader do
  @moduledoc "Display contract for the detail-page header."

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow

  @enforce_keys [:id, :title, :state, :origin, :attempt_count, :tried_count]
  defstruct [
    :id,
    :title,
    :state,
    :origin,
    :attempt_count,
    :tried_count,
    :criteria_summary,
    :inserted_at
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: PursuitRow.state(),
          origin: PursuitRow.origin(),
          attempt_count: non_neg_integer(),
          tried_count: non_neg_integer(),
          criteria_summary: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }
end
