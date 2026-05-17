defmodule MediaCentarr.Acquisition.Pursuits.Recipe do
  @moduledoc """
  Value-object projection of a pursuit's search recipe — the typed sum
  of "what is this pursuit looking for".

  Consumers (`QueryBuilder`, `TitleMatcher`, the search helpers in
  `Acquisition`) pattern-match on this struct instead of reaching into
  the raw discriminator + variant columns on the pursuit row. Single
  touchpoint for the recipe shape; adding a new variant means editing
  one module rather than every consumer.

  Two variants, discriminated by `:type`:

    * `:tmdb` — TMDB-typed lookup. Populated: `title`, `tmdb_id`,
      `tmdb_type` (`:movie | :tv`), optional `season_number` /
      `episode_number` (TV) or `year` (movies).
    * `:prowlarr_query` — free-form Prowlarr query. Populated:
      `title`, `manual_query` (brace syntax allowed; expanded by
      `QueryExpander`).

  Build with `from/1`. Pure module — no I/O, no DB.
  """

  alias MediaCentarr.Acquisition.Pursuits.Pursuit

  @enforce_keys [:type, :title]
  defstruct [
    :type,
    :title,
    :tmdb_id,
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
          tmdb_id: String.t() | nil,
          tmdb_type: tmdb_type() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          year: integer() | nil,
          manual_query: String.t() | nil
        }

  @spec from(Pursuit.t()) :: t()
  def from(%Pursuit{recipe_type: "tmdb"} = pursuit) do
    %__MODULE__{
      type: :tmdb,
      title: pursuit.title,
      tmdb_id: pursuit.tmdb_id,
      tmdb_type: tmdb_type_atom(pursuit.tmdb_type),
      season_number: pursuit.season_number,
      episode_number: pursuit.episode_number,
      year: pursuit.year
    }
  end

  def from(%Pursuit{recipe_type: "prowlarr_query"} = pursuit) do
    %__MODULE__{
      type: :prowlarr_query,
      title: pursuit.title,
      manual_query: pursuit.manual_query
    }
  end

  defp tmdb_type_atom("movie"), do: :movie
  defp tmdb_type_atom("tv"), do: :tv
  defp tmdb_type_atom(nil), do: nil

  @doc """
  Projects this recipe into the `MediaCentarr.Search.Criteria` shape
  consumed by `Search.QueryBuilder` and `Search.TitleMatcher`.

  Both recipe types project — TitleMatcher itself rejects
  `:prowlarr_query` criteria (the user-typed query bypasses title
  matching), but QueryBuilder uses them to build the manual-query
  search.
  """
  @spec to_criteria(t()) :: MediaCentarr.Search.Criteria.t()
  def to_criteria(%__MODULE__{type: :tmdb} = recipe) do
    %MediaCentarr.Search.Criteria{
      type: :tmdb,
      title: recipe.title,
      tmdb_type: recipe.tmdb_type,
      season_number: recipe.season_number,
      episode_number: recipe.episode_number,
      year: recipe.year
    }
  end

  def to_criteria(%__MODULE__{type: :prowlarr_query} = recipe) do
    %MediaCentarr.Search.Criteria{
      type: :prowlarr_query,
      title: recipe.title,
      manual_query: recipe.manual_query
    }
  end
end
