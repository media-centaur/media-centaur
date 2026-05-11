defmodule MediaCentarr.Acquisition.ViewModels.PursuitHeader do
  @moduledoc "Identity contract for the detail-page header."

  alias MediaCentarr.Acquisition.ViewModels.PursuitRow
  alias MediaCentarr.Acquisition.ViewModels.Target

  @enforce_keys [:id, :title, :state, :target]
  defstruct [:id, :title, :state, :target, :criteria_summary]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: PursuitRow.state(),
          target: Target.t(),
          criteria_summary: String.t() | nil
        }
end
