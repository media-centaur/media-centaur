defmodule MediaCentaur.Features.Feature do
  @moduledoc """
  One entry of the feature registry (`MediaCentaur.Features`): what the
  feature is called on the Feature flags row and in its off state, the one
  line that says what it is, the flag's default, and the stage.
  """

  @type stage :: :development | :optional

  @type t :: %__MODULE__{
          id: atom(),
          name: String.t(),
          description: String.t(),
          default: boolean(),
          stage: stage()
        }

  @enforce_keys [:id, :name, :description, :default, :stage]
  defstruct [:id, :name, :description, :default, :stage]
end
