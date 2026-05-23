defmodule MediaCentaur.Search.TitleMatcher do
  @moduledoc """
  Verifies that a Prowlarr `SearchResult` actually corresponds to the
  caller's match `Criteria`.

  Without this gate, Prowlarr's loose relevance ranking lets unrelated
  releases through whenever the show title is short or common
  ("Sample Show Fifteen", "Lost"). Episode synopses or even episode titles
  containing the word are enough to score a hit, and the worker
  previously trusted the first acceptable-quality result.

  ## Rules

  Each result's title is parsed by `MediaCentaur.Parser` and required
  to match the supplied criteria on:

    * media type — TV criteria only accept parsed TV releases, movie
      criteria only accept parsed movies
    * normalised show/movie title — case-folded, alphanumerics only,
      whitespace collapsed (so `Sample's Show Twelve` matches
      `Samples.Show.Twelve`)
    * season + episode — episode-keyed criteria require both to match
      exactly; season-pack criteria require season match and reject
      results that pin a specific episode
    * year (movies only) — must match if the parser extracted one;
      missing year is tolerated

  Only the `:tmdb` criteria variant is matched here. Prowlarr-query
  criteria route directly to the decision card and don't apply title
  matching (the user already trusts the query they typed).

  Pure module — no I/O, no DB.
  """

  alias MediaCentaur.Search.{Criteria, SearchResult}
  alias MediaCentaur.Parser

  @spec matches?(SearchResult.t(), Criteria.t()) :: boolean()
  def matches?(%SearchResult{title: title}, %Criteria{type: :tmdb} = criteria) do
    title
    |> Parser.parse()
    |> matches_criteria?(criteria)
  end

  def matches?(%SearchResult{}, %Criteria{}), do: false

  defp matches_criteria?(%Parser.Result{type: :tv} = parsed, %Criteria{tmdb_type: :tv} = criteria) do
    title_matches?(parsed.title, criteria.title) and
      parsed.season == criteria.season_number and
      parsed.episode == criteria.episode_number
  end

  defp matches_criteria?(%Parser.Result{type: :movie} = parsed, %Criteria{tmdb_type: :movie} = criteria) do
    title_matches?(parsed.title, criteria.title) and year_matches?(parsed.year, criteria.year)
  end

  defp matches_criteria?(_parsed, _criteria), do: false

  defp title_matches?(parsed_title, expected_title)
       when is_binary(parsed_title) and is_binary(expected_title) do
    normalize(parsed_title) == normalize(expected_title)
  end

  defp title_matches?(_, _), do: false

  defp year_matches?(nil, _expected_year), do: true
  defp year_matches?(_parsed_year, nil), do: true
  defp year_matches?(parsed_year, expected_year), do: parsed_year == expected_year

  defp normalize(title) do
    title
    |> String.downcase()
    |> String.replace(~r/['']/u, "")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end
end
