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

  alias MediaCentaur.Search.{Criteria, ReleaseCoverage, SearchResult}
  alias MediaCentaur.Parser

  # Tokens that begin a release's scope/quality tail — everything before
  # the first one is the show-identity prefix `coverage/2` verifies.
  @scope_tail ~r/\b(?:S\d{1,2}\b|Season[\s._-]+\d{1,2}\b|COMPLETE\b|Complete[\s._-]+(?:Series|Collection)\b)/i
  @trailing_year ~r/\b(?:19|20)\d{2}\s*$/

  @spec matches?(SearchResult.t(), Criteria.t()) :: boolean()
  def matches?(%SearchResult{title: title}, %Criteria{type: :tmdb} = criteria) do
    title
    |> Parser.parse()
    |> matches_criteria?(criteria)
  end

  def matches?(%SearchResult{}, %Criteria{}), do: false

  @doc """
  Identity + scope for the coverage ladder (media-search campaign
  Phase 2): verifies the release belongs to the criteria's show, then
  returns its classified `ReleaseCoverage` scope so the planner can
  compute which wanted units it covers.

  Unlike `matches?/2` — which stays the strict want-equality gate the
  auto-grab worker uses (an episode pursuit must never silently grab a
  season pack) — `coverage/2` accepts every scope shape; choosing
  *whether* a pack is the right grab is the planner's decision, not the
  matcher's.

  TV criteria only: movies have no episode scope, and prowlarr-query
  criteria carry no canonical title to verify against.
  """
  @spec coverage(SearchResult.t(), Criteria.t()) :: {:ok, ReleaseCoverage.t()} | :no_match
  def coverage(%SearchResult{title: title}, %Criteria{type: :tmdb, tmdb_type: :tv} = criteria) do
    case ReleaseCoverage.classify(title) do
      :unknown ->
        :no_match

      {:episode, _season, _episode} = scope ->
        # Single episodes go through the Parser path — the same
        # battle-tested identity check `matches?/2` uses.
        parsed = Parser.parse(title)

        if parsed.type == :tv and title_matches?(parsed.title, criteria.title),
          do: {:ok, scope},
          else: :no_match

      scope ->
        if pack_title_matches?(title, criteria.title), do: {:ok, scope}, else: :no_match
    end
  end

  def coverage(%SearchResult{}, %Criteria{}), do: :no_match

  # Pack shapes (S02.COMPLETE, S01-S05, Complete Series) don't parse as
  # files, so identity comes from the prefix before the first scope
  # token — normalized, with a trailing year token tolerated (release
  # groups often bake the show's year in).
  defp pack_title_matches?(title, expected_title) do
    case Regex.split(@scope_tail, title, parts: 2) do
      [prefix, _tail] ->
        prefix
        |> normalize()
        |> String.replace(@trailing_year, "")
        |> String.trim()
        |> Kernel.==(normalize(expected_title))

      _no_scope_token ->
        false
    end
  end

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
