defmodule MediaCentarr.Acquisition.ViewModels.CurrentAction do
  @moduledoc "What the pursuit is doing right now — one verb plus context."

  @enforce_keys [:verb, :description, :severity]
  defstruct [:verb, :description, :severity]

  @type severity :: :info | :success | :warning | :error
  @type t :: %__MODULE__{
          verb: String.t(),
          description: String.t(),
          severity: severity()
        }
end
