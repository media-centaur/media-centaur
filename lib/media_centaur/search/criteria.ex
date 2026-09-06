defmodule MediaCentaur.Search.Criteria do
  @moduledoc """
  Search input shape consumed by `MediaCentaur.Search.TitleMatcher`.

  Decouples Search from any specific Acquisition concept: callers
  (currently `Acquisition.Pursuits.Recipe`) project their domain
  shape into this struct before crossing the Search boundary.

  Keeping this struct in Search inverts the dependency cleanly —
  Search does not need to know what a Pursuit / Recipe is; it just
  needs "the criteria I am matching results against".
  """

  @enforce_keys [:type, :title]
  defstruct [
    :type,
    :title,
    :tmdb_type,
    :season_number,
    :episode_number,
    :year,
    :manual_query,
    :run,
    :imdb_id,
    :tmdb_id,
    :tvdb_id,
    :original_title,
    origin_country: []
  ]

  @type type :: :tmdb | :prowlarr_query
  @type tmdb_type :: :movie | :tv

  @type t :: %__MODULE__{
          type: type(),
          title: String.t(),
          tmdb_type: tmdb_type() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          year: integer() | nil,
          manual_query: String.t() | nil,
          # The broadcast run (cour) this residual belongs to, when it is
          # a *later* run — a `CourSegmentation` run map. Drives
          # cour-aware query generation (`QueryBuilder`). Nil / first run
          # → the regular `Season N` queries.
          run: map() | nil,
          # External identity of the wanted title, as TMDB spells it —
          # the exact answer `TitleMatcher` prefers over parsing a
          # release name. Nil where TMDB supplied none (or the plan
          # predates the resolve seam), which leaves the title + year
          # heuristic in charge for that criteria.
          imdb_id: String.t() | nil,
          tmdb_id: String.t() | nil,
          tvdb_id: String.t() | nil,
          # The title in its original language, when TMDB's canonical
          # `title` is a localised one. Release groups name a foreign
          # title either way, so the matcher accepts both and the movie
          # query builder asks for both.
          original_title: String.t() | nil,
          # TMDB `origin_country` ISO codes for the show (TV only, e.g.
          # `["US"]`). Lets `TitleMatcher` accept scene country tags
          # (`Title.US.S01`) that release groups append to disambiguate
          # same-title remakes. Empty → tags are rejected (unknown origin).
          origin_country: [String.t()]
        }
end
