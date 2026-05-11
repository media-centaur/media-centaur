defmodule MediaCentarr.Acquisition.ViewModels.Recipe do
  @moduledoc """
  The pursuit's *search recipe* — the typed description of what it's
  looking for. Used by the detail-page header to render "what kind of
  thing is this pursuit chasing".

  Two variants:

  - `recipe_type: :tmdb` — a TMDB-typed lookup. Carries
    `tmdb_type ∈ {:movie, :tv}`, optional `tmdb_id`, season/episode/year.
  - `recipe_type: :prowlarr_query` — a free-form Prowlarr query string
    (brace syntax allowed; expanded by `QueryExpander`). Carries
    `manual_query`.
  """

  @enforce_keys [:recipe_type]
  defstruct [
    :recipe_type,
    :tmdb_type,
    :tmdb_id,
    :season_number,
    :episode_number,
    :year,
    :manual_query
  ]

  @type recipe_type :: :tmdb | :prowlarr_query

  @type t :: %__MODULE__{
          recipe_type: recipe_type(),
          tmdb_type: String.t() | nil,
          tmdb_id: String.t() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          year: integer() | nil,
          manual_query: String.t() | nil
        }
end
