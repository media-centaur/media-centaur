defmodule MediaCentarr.Acquisition.ViewModels.DecisionCard do
  @moduledoc "Display contract for the alternatives picker."

  alias MediaCentarr.Acquisition.ViewModels.Alternative

  @enforce_keys [:pursuit_id, :prompt, :alternatives]
  defstruct [:pursuit_id, :prompt, :alternatives, :loading?]

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          prompt: String.t(),
          alternatives: [Alternative.t()],
          loading?: boolean()
        }
end
