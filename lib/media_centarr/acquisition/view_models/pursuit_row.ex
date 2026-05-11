defmodule MediaCentarr.Acquisition.ViewModels.PursuitRow do
  @moduledoc "Display contract for one row in the activity zone."

  alias MediaCentarr.Acquisition.ViewModels.TimelineEntry

  @enforce_keys [:id, :title, :state, :origin, :attempt_count, :recent_events, :detail_path]
  defstruct [
    :id,
    :title,
    :state,
    :origin,
    :attempt_count,
    :recent_events,
    :detail_path,
    :release_title,
    :grab_status,
    :inserted_at,
    :updated_at
  ]

  @type state ::
          :active
          | :needs_decision
          | :satisfied
          | :exhausted
          | :cancelled

  @type origin :: :auto | :manual

  @type grab_status :: :searching | :snoozed | :grabbed | :abandoned | :cancelled

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: state(),
          origin: origin(),
          attempt_count: non_neg_integer(),
          recent_events: [TimelineEntry.t()],
          detail_path: String.t(),
          release_title: String.t() | nil,
          grab_status: grab_status() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
