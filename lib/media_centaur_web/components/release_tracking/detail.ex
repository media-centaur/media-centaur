defmodule MediaCentaurWeb.Components.ReleaseTracking.Detail do
  @moduledoc """
  View-model for the per-title detail slide-over: the title, its automation
  posture, its release timeline, and recent per-title activity. Built by the
  LiveView from `ReleaseTracking` + `Acquisition` reads and rendered by
  `DetailPanel`.
  """

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  defstruct [
    :item_id,
    :name,
    :media_type,
    :backdrop_path,
    :acquisition?,
    :auto_grab,
    timeline: [],
    activity: []
  ]

  @type activity_entry :: %{text: String.t(), at: String.t()}

  @type t :: %__MODULE__{
          item_id: String.t(),
          name: String.t(),
          media_type: :movie | :tv_series,
          backdrop_path: String.t() | nil,
          acquisition?: boolean(),
          auto_grab: %{on?: boolean(), label: String.t()},
          timeline: [Event.t()],
          activity: [activity_entry()]
        }
end
