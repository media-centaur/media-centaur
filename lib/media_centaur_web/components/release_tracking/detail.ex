defmodule MediaCentaurWeb.Components.ReleaseTracking.Detail do
  @moduledoc """
  View-model for the per-title depth surface (the title modal): the title,
  its automation posture, its release timeline, recent per-title activity,
  and when tracking began. Built by the LiveView from `ReleaseTracking` +
  `Acquisition` reads and rendered by `TitleModal`.
  """

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  defstruct [
    :item_id,
    :name,
    :media_type,
    :backdrop_url,
    :logo_url,
    :acquisition?,
    :auto_grab,
    :tracking_since,
    lower_quality_accepted?: false,
    timeline: [],
    activity: []
  ]

  @type activity_entry :: %{text: String.t(), at: String.t()}

  @type t :: %__MODULE__{
          item_id: String.t(),
          name: String.t(),
          media_type: :movie | :tv_series,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          acquisition?: boolean(),
          auto_grab: %{on?: boolean(), label: String.t()},
          lower_quality_accepted?: boolean(),
          tracking_since: DateTime.t() | NaiveDateTime.t() | nil,
          timeline: [Event.t()],
          activity: [activity_entry()]
        }
end
