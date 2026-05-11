defmodule MediaCentarr.Acquisition.ViewModels.NextStep do
  @moduledoc "What's expected to happen next on this pursuit (automatic)."

  @enforce_keys [:description]
  defstruct [:description]

  @type t :: %__MODULE__{description: String.t()}
end
