defmodule MediaCentarr.ReleaseTracking.Views.ComingUpItem do
  @moduledoc """
  View-model for one entry in the Coming Up projection.

  Mirrors the field shape produced by
  `MediaCentarr.ReleaseTracking.list_releases_between/3`. The `:status`
  field defaults to `:scheduled`; callers (e.g. HomeLive) may enrich
  with a live grab status from Acquisition.
  """

  alias MediaCentarr.ReleaseTracking.Views.ComingUpItemRef

  @enforce_keys [:item, :air_date]
  defstruct [
    :item,
    :air_date,
    :season_number,
    :episode_number,
    :backdrop_url,
    :logo_url,
    status: :scheduled
  ]

  @type t :: %__MODULE__{
          item: ComingUpItemRef.t(),
          air_date: Date.t(),
          season_number: integer() | nil,
          episode_number: integer() | nil,
          status: atom(),
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil
        }
end
