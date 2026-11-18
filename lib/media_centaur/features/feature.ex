defmodule MediaCentaur.Features.Feature do
  @moduledoc """
  One entry of the feature registry (`MediaCentaur.Features`): what the
  feature is called on the Feature flags row and in its off state, the one
  line that says what it is, the flag's default, and the stage.

  `requires` names the feature this one is part of, when there is one: it
  is on only while that feature is on, and its Feature flags row is listed
  only then.
  """

  @type stage :: :development | :optional

  @type t :: %__MODULE__{
          id: atom(),
          name: String.t(),
          description: String.t(),
          default: boolean(),
          stage: stage(),
          requires: atom() | nil
        }

  @enforce_keys [:id, :name, :description, :default, :stage]
  defstruct [:id, :name, :description, :default, :stage, :requires]
end
