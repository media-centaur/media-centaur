defmodule MediaCentaurWeb.StatusLive.SubsystemView do
  @moduledoc "Typed view-model for one subsystem tile (MC0008 typed-attr target)."

  @enforce_keys [:component, :label, :glyph, :state, :error_count, :warning_count]
  defstruct [:component, :label, :glyph, :state, :error_count, :warning_count]

  @type t :: %__MODULE__{
          component: atom(),
          label: String.t(),
          glyph: String.t(),
          state: :ok | :warning | :error,
          error_count: non_neg_integer(),
          warning_count: non_neg_integer()
        }
end
