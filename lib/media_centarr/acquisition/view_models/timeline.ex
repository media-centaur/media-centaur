defmodule MediaCentarr.Acquisition.ViewModels.Timeline do
  @moduledoc "Display contract for the timeline component."

  alias MediaCentarr.Acquisition.ViewModels.TimelineEntry

  @enforce_keys [:pursuit_id, :entries]
  defstruct [:pursuit_id, :entries]

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          entries: [TimelineEntry.t()]
        }
end
