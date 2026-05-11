defmodule MediaCentarr.Acquisition.QueryBuilder do
  @moduledoc """
  Builds an ordered list of Prowlarr search queries for a pursuit's recipe.

  Returns `[{query_string, opts}]` ordered best-to-worst — the worker
  tries each in turn until one yields acceptable results. Opts may
  carry `:type` (`:movie` or `:tv`) and `:year` (movies only — episode
  release titles do not embed the show's first-air year, so adding it
  usually shrinks results unhelpfully).

  ## Recipe variants

  - `recipe_type: "tmdb"` → TMDB metadata drives query shape
    (`title [year]` for movies, `title SxxEyy` / `title Season N` for
    TV). One or more concrete query strings, no brace expansion.
  - `recipe_type: "prowlarr_query"` → the user-typed `manual_query`,
    expanded via `QueryExpander` (brace syntax allowed). No type/year
    hints (Prowlarr's category routing is the user's responsibility).
    Every result is considered a match — the worker routes through
    the decision card for the user to pick.

  Pure function module — no I/O, no DB.
  """

  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.QueryExpander
  alias MediaCentarr.Format

  @type opt :: {:type, :movie | :tv} | {:year, integer()}
  @type query :: {String.t(), [opt()]}

  @spec build(Pursuit.t()) :: [query()]
  def build(%Pursuit{recipe_type: "tmdb", tmdb_type: "movie"} = p), do: build_movie(p)
  def build(%Pursuit{recipe_type: "tmdb", tmdb_type: "tv"} = p), do: build_tv(p)
  def build(%Pursuit{recipe_type: "prowlarr_query"} = p), do: build_prowlarr_query(p)

  defp build_movie(%Pursuit{title: title, year: nil}), do: [{title, [type: :movie]}]

  defp build_movie(%Pursuit{title: title, year: year}) when is_integer(year) do
    [{"#{title} #{year}", [type: :movie, year: year]}]
  end

  defp build_tv(%Pursuit{title: title, season_number: season, episode_number: nil})
       when is_integer(season) do
    [
      {"#{title} Season #{season}", [type: :tv]},
      {"#{title} #{season_tag(season)}", [type: :tv]}
    ]
  end

  defp build_tv(%Pursuit{title: title, season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    [
      {"#{title} #{season_tag(season)}#{episode_tag(episode)}", [type: :tv]},
      {"#{title} Season #{season}", [type: :tv]}
    ]
  end

  # Whole-series fallback (no season/episode known) — rare in the
  # auto-acquisition flow because Refresher always emits a release with
  # episode info, but legitimate when a manual TMDB pursuit targets the
  # series itself.
  defp build_tv(%Pursuit{title: title, season_number: nil, episode_number: nil}) do
    [{title, [type: :tv]}]
  end

  defp build_prowlarr_query(%Pursuit{manual_query: nil}), do: []

  defp build_prowlarr_query(%Pursuit{manual_query: query}) when is_binary(query) do
    case QueryExpander.expand(query) do
      {:ok, parts} -> Enum.map(parts, &{&1, []})
      {:error, _} -> [{query, []}]
    end
  end

  defp season_tag(season), do: "S" <> Format.pad2(season)
  defp episode_tag(episode), do: "E" <> Format.pad2(episode)
end
