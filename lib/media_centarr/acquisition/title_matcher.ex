defmodule MediaCentarr.Acquisition.TitleMatcher do
  @moduledoc """
  Verifies that a Prowlarr `SearchResult` actually corresponds to the
  pursuit's TMDB recipe.

  Without this gate, Prowlarr's loose relevance ranking lets unrelated
  releases through whenever the show title is short or common
  ("Sample Show Fifteen", "Lost"). Episode synopses or even episode titles
  containing the word are enough to score a hit, and the worker
  previously trusted the first acceptable-quality result.

  ## Rules

  Each result's title is parsed by `MediaCentarr.Parser` and required
  to match the pursuit's recipe on:

    * media type — TV recipes only accept parsed TV releases, movie
      recipes only accept parsed movies
    * normalised show/movie title — case-folded, alphanumerics only,
      whitespace collapsed (so `Sample's Show Twelve` matches
      `Samples.Show.Twelve`)
    * season + episode — episode-keyed recipes require both to match
      exactly; season-pack recipes require season match and reject
      results that pin a specific episode
    * year (movies only) — must match if the parser extracted one;
      missing year is tolerated

  Only the `recipe_type = "tmdb"` variant is matched here. Query-recipe
  pursuits route directly to the decision card and don't apply title
  matching (the user already trusts the query they typed).

  Pure module — no I/O, no DB.
  """

  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.SearchResult
  alias MediaCentarr.Parser

  @spec matches?(SearchResult.t(), Pursuit.t()) :: boolean()
  def matches?(%SearchResult{title: title}, %Pursuit{recipe_type: "tmdb"} = pursuit) do
    title
    |> Parser.parse()
    |> matches_recipe?(pursuit)
  end

  def matches?(%SearchResult{}, %Pursuit{}), do: false

  defp matches_recipe?(%Parser.Result{type: :tv} = parsed, %Pursuit{tmdb_type: "tv"} = p) do
    title_matches?(parsed.title, p.title) and
      parsed.season == p.season_number and
      parsed.episode == p.episode_number
  end

  defp matches_recipe?(%Parser.Result{type: :movie} = parsed, %Pursuit{tmdb_type: "movie"} = p) do
    title_matches?(parsed.title, p.title) and year_matches?(parsed.year, p.year)
  end

  defp matches_recipe?(_parsed, _pursuit), do: false

  defp title_matches?(parsed_title, recipe_title)
       when is_binary(parsed_title) and is_binary(recipe_title) do
    normalize(parsed_title) == normalize(recipe_title)
  end

  defp title_matches?(_, _), do: false

  defp year_matches?(nil, _recipe_year), do: true
  defp year_matches?(_parsed_year, nil), do: true
  defp year_matches?(parsed_year, recipe_year), do: parsed_year == recipe_year

  defp normalize(title) do
    title
    |> String.downcase()
    |> String.replace(~r/['']/u, "")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end
end
