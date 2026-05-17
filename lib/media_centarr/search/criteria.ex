defmodule MediaCentarr.Search.Criteria do
  @moduledoc """
  Search input shape consumed by `MediaCentarr.Search.TitleMatcher`.

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
    :manual_query
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
          manual_query: String.t() | nil
        }
end
