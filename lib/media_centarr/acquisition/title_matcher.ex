defmodule MediaCentarr.Acquisition.TitleMatcher do
  @moduledoc """
  Verifies that a Prowlarr `SearchResult` actually corresponds to the
  `Grab` it is supposed to satisfy.

  Without this gate, Prowlarr's loose relevance ranking lets unrelated
  releases through whenever the show title is short or common
  ("Sample Show Fifteen", "Lost"). Episode synopses or even episode titles
  containing the word are enough to score a hit, and the worker
  previously trusted the first acceptable-quality result.

  ## Rules

  Each result's title is parsed by `MediaCentarr.Parser` and required to
  match the grab on:

    * media type — TV grabs only accept parsed TV releases, movie grabs
      only accept parsed movies
    * normalised show/movie title — case-folded, alphanumerics only,
      whitespace collapsed (so `Sample's Show Twelve` matches `Samples.Show.Twelve`)
    * season + episode — episode grabs require both to match exactly;
      season-pack grabs require season match and reject results that
      pin a specific episode
    * year (movies only) — must match if the parser extracted one;
      missing year is tolerated

  Pure module — no I/O, no DB.
  """

  alias MediaCentarr.Acquisition.{Grab, SearchResult}
  alias MediaCentarr.Parser

  @spec matches?(SearchResult.t(), Grab.t()) :: boolean()
  def matches?(%SearchResult{title: title}, %Grab{} = grab) do
    title
    |> Parser.parse()
    |> matches_grab?(grab)
  end

  defp matches_grab?(%Parser.Result{type: :tv} = parsed, %Grab{tmdb_type: "tv"} = grab) do
    title_matches?(parsed.title, grab.title) and
      parsed.season == grab.season_number and
      parsed.episode == grab.episode_number
  end

  defp matches_grab?(%Parser.Result{type: :movie} = parsed, %Grab{tmdb_type: "movie"} = grab) do
    title_matches?(parsed.title, grab.title) and year_matches?(parsed.year, grab.year)
  end

  defp matches_grab?(_parsed, _grab), do: false

  defp title_matches?(parsed_title, grab_title) when is_binary(parsed_title) and is_binary(grab_title) do
    normalize(parsed_title) == normalize(grab_title)
  end

  defp title_matches?(_, _), do: false

  defp year_matches?(nil, _grab_year), do: true
  defp year_matches?(_parsed_year, nil), do: true
  defp year_matches?(parsed_year, grab_year), do: parsed_year == grab_year

  # Apostrophes are contracted (not split into separate tokens) so
  # `Marvel's` normalises to `marvels`, matching a TMDB-canonical title
  # of `Samples Show Twelve` against a release tagged `Sample's.Show.Twelve`.
  defp normalize(title) do
    title
    |> String.downcase()
    |> String.replace(~r/['']/u, "")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end
end
