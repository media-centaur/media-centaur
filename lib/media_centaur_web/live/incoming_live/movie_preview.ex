defmodule MediaCentaurWeb.IncomingLive.MoviePreview do
  @moduledoc """
  View-model for the plan modal's `:movie_confirm` stage — a detail-page
  shaped preview of the movie the user just picked from media search, so
  the confirmation surface shows the same identity cues (backdrop, logo,
  tagline, director, top cast, facets) the library's movie detail panel
  shows for a movie already owned.

  Built by `IncomingLive.PlanLogic.movie_preview/2` from a raw TMDB
  payload via `TMDB.Mapper` — the same derivation the import pipeline
  uses — so the preview can never drift from what ingestion would record.
  Absent TMDB fields collapse to `nil`/empty so the template drops them.

  `year` is the movie's canonical release year (`TMDB.Mapper`'s
  earliest-typed-release derivation, not the primary `release_date`), and
  is the year `Plans.create_movie_plan/2` stamps on the plan so the
  indexer query matches how releases are actually tagged.

  `facets` are `Detail.Facet` structs (rendered by `Detail.FacetStrip`),
  `cast` are `Library.Person` structs (the library's cast shape), and the
  image fields are absolute TMDB CDN URLs — a not-yet-owned movie has no
  local artwork, so the preview hotlinks TMDB rather than the
  `/media-images/` path the owned detail panel serves from.
  """

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.Facet

  @type t :: %__MODULE__{
          tmdb_id: String.t(),
          title: String.t() | nil,
          year: integer() | nil,
          tagline: String.t() | nil,
          overview: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          poster_url: String.t() | nil,
          metadata_items: [String.t()],
          facets: [Facet.t()],
          cast: [Person.t()],
          in_library?: boolean()
        }

  @enforce_keys [:tmdb_id, :in_library?]
  defstruct tmdb_id: nil,
            title: nil,
            year: nil,
            tagline: nil,
            overview: nil,
            backdrop_url: nil,
            logo_url: nil,
            poster_url: nil,
            metadata_items: [],
            facets: [],
            cast: [],
            in_library?: false
end
