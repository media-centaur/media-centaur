defmodule MediaCentaur.ReleaseTracking.TitleResult do
  @moduledoc """
  One TMDB title-search hit — the unified result both title-search
  surfaces (omnibox dropdown, track flow) consume, built once by
  `MediaCentaur.ReleaseTracking.Acquisition.search_tmdb/1`.

  A *title* result (a movie or show from TMDB's multi search), as
  opposed to `MediaCentaur.Search.SearchResult` — a *release* result
  from an indexer. The two searches stay separate by design.
  """

  @enforce_keys [:tmdb_id, :media_type, :name]
  defstruct [
    :tmdb_id,
    :media_type,
    :name,
    :year,
    :release_date,
    :poster_path,
    :backdrop_path,
    :overview,
    tracked?: false
  ]

  @type t :: %__MODULE__{
          tmdb_id: integer(),
          media_type: :movie | :tv_series,
          name: String.t(),
          year: String.t() | nil,
          release_date: Date.t() | nil,
          poster_path: String.t() | nil,
          backdrop_path: String.t() | nil,
          overview: String.t() | nil,
          tracked?: boolean()
        }
end
