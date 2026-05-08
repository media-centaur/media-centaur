defmodule MediaCentarrWeb.ViewModel.SeasonView do
  @moduledoc """
  Presentation view of one season on the TV-series detail page.

  Two `kind`s:

    * `:library` — projects an existing `MediaCentarr.Library.Season`.
      Carries the watched/total counts so the section header can show
      "3 remaining".
    * `:future` — TMDB knows the season exists but no library files
      yet. `items` are all `EpisodeListItem.Upcoming`. Watched-count
      copy is suppressed in the renderer (nothing to count).

  `items` is ordered by episode number; the type is
  `[MediaCentarrWeb.ViewModel.EpisodeListItem.t()]`.

  Built by `MediaCentarrWeb.ViewModel.SeriesDetail.compose/2`.
  """

  alias MediaCentarrWeb.ViewModel.EpisodeListItem

  @enforce_keys [:season_number, :kind, :items]
  defstruct [
    :season_number,
    :name,
    :kind,
    :items,
    :extras,
    :watched_count,
    :total_count
  ]

  @type kind :: :library | :future
  @type t :: %__MODULE__{
          season_number: non_neg_integer(),
          name: String.t() | nil,
          kind: kind,
          items: [EpisodeListItem.t()],
          extras: list() | nil,
          watched_count: non_neg_integer() | nil,
          total_count: non_neg_integer() | nil
        }
end
