defmodule MediaCentarr.Acquisition.ViewModels.PursuitHeader do
  @moduledoc "Identity contract for the detail-page header."

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow
  alias MediaCentarr.Acquisition.ViewModels.Recipe

  @enforce_keys [:id, :title, :state, :recipe]
  defstruct [:id, :title, :state, :recipe, :criteria_summary]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: PursuitRow.state(),
          recipe: Recipe.t(),
          criteria_summary: String.t() | nil
        }
end
