defmodule MediaCentarr.Controls.Binding do
  @moduledoc """
  One entry in the controls catalog.

  The catalog lists every action the app responds to. Each binding carries
  its category, display metadata, and default keyboard/gamepad values.
  Unbound defaults are represented as `nil`.
  """

  @type category :: :navigation | :zones | :playback | :system
  @type scope :: :input_system | :global

  @type t :: %__MODULE__{
          id: atom(),
          category: category(),
          name: String.t(),
          description: String.t(),
          default_key: String.t() | nil,
          default_button: non_neg_integer() | nil,
          scope: scope()
        }

  defstruct [
    :id,
    :category,
    :name,
    :description,
    :default_key,
    :default_button,
    :scope
  ]
end
