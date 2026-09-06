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

  Identity is settled by **external id** whenever both sides carry one.
  Prowlarr's results carry the indexer's own `imdbId` / `tmdbId` /
  `tvdbId`, and TMDB-recipe criteria carry the same ids for the wanted
  title, so the comparison is exact where parsing a release name is a
  heuristic. `compare_external_ids/2` returns:

    * `:match` — at least one id pair agrees. Identity is proven, so the
      title and (movies) year checks are skipped entirely: a
      tracker-prefixed name or a release tagged with the festival year
      still matches.
    * `:mismatch` — ids were comparable and none agreed. The result is
      rejected outright, which title parsing can never assert. One id
      agreeing outweighs another disagreeing: indexers mis-tag a single
      field far more often than they get every field wrong.
    * `:unknown` — nothing comparable (either side missing every id).
      The title and year rules below decide, unchanged.

  An id names the *title*, not the *scope*: a `tvdbId` identifies the
  series, so season/episode equality and the media-type check still
  apply to an id-matched result.

  Each result's title is parsed by `MediaCentaur.Parser` and required
  to match the supplied criteria on:

    * media type — TV criteria only accept parsed TV releases, movie
      criteria only accept parsed movies
    * normalised show/movie title — case-folded, alphanumerics only,
      whitespace collapsed (so `Sample's Show Twelve` matches
      `Samples.Show.Twelve`). A trailing scene country tag
      (`Sample.Show.US.S01E01`) is accepted only when the criteria's
      `origin_country` includes it — release groups append the tag to
      disambiguate same-title remakes, so a mismatched or unverifiable
      tag means the release is (or may be) the other show
    * season + episode — episode-keyed criteria require both to match
      exactly; season-pack criteria require season match and reject
      results that pin a specific episode
    * year (movies only) — must match within ±1 if the parser extracted
      one (festival premiere vs theatrical release routinely differ by
      a year); missing year is tolerated. Applies only to results whose
      identity is `:unknown` — an id match settles the year question

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

  # Scene country tags → TMDB `origin_country` ISO 3166-1 codes. The
  # scene writes UK where TMDB writes GB; the rest coincide.
  @country_tags %{"us" => "US", "uk" => "GB", "gb" => "GB", "au" => "AU", "ca" => "CA", "nz" => "NZ"}

  @spec matches?(SearchResult.t(), Criteria.t()) :: boolean()
  def matches?(%SearchResult{} = result, %Criteria{type: :tmdb} = criteria) do
    case compare_external_ids(result, criteria) do
      :mismatch ->
        false

      identity ->
        result.title
        |> Parser.parse()
        |> matches_criteria?(criteria, identity)
    end
  end

  def matches?(%SearchResult{}, %Criteria{}), do: false

  @doc """
  Compares the external ids the indexer declared for a release against
  the ids of the wanted title — `:match` when any pair agrees,
  `:mismatch` when pairs were comparable and none did, `:unknown` when
  there was nothing to compare. See the module rules.
  """
  @spec compare_external_ids(SearchResult.t(), Criteria.t()) :: :match | :mismatch | :unknown
  def compare_external_ids(%SearchResult{} = result, %Criteria{} = criteria) do
    [
      {result.imdb_id, criteria.imdb_id},
      {result.tmdb_id, criteria.tmdb_id},
      {result.tvdb_id, criteria.tvdb_id}
    ]
    |> Enum.filter(fn {declared, wanted} -> is_binary(declared) and is_binary(wanted) end)
    |> case do
      [] ->
        :unknown

      pairs ->
        if Enum.any?(pairs, fn {declared, wanted} -> declared == wanted end), do: :match, else: :mismatch
    end
  end

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
  def coverage(%SearchResult{title: title} = result, %Criteria{type: :tmdb, tmdb_type: :tv} = criteria) do
    identity = compare_external_ids(result, criteria)

    case {identity, ReleaseCoverage.classify(title)} do
      {:mismatch, _scope} ->
        :no_match

      {_identity, :unknown} ->
        :no_match

      {identity, {:episode, _season, _episode} = scope} ->
        # Single episodes go through the Parser path — the same
        # battle-tested identity check `matches?/2` uses.
        parsed = Parser.parse(title)

        if parsed.type == :tv and title_verified?(parsed.title, criteria, identity),
          do: {:ok, scope},
          else: :no_match

      {identity, scope} ->
        if pack_title_matches?(title, criteria, identity), do: {:ok, scope}, else: :no_match
    end
  end

  def coverage(%SearchResult{}, %Criteria{}), do: :no_match

  # Pack shapes (S02.COMPLETE, S01-S05, Complete Series) don't parse as
  # files, so identity comes from the prefix before the first scope
  # token — normalized, with a trailing year token tolerated (release
  # groups often bake the show's year in).
  defp pack_title_matches?(title, %Criteria{} = criteria, identity) do
    case Regex.split(@scope_tail, title, parts: 2) do
      [prefix, _tail] ->
        prefix
        |> normalize()
        |> String.replace(@trailing_year, "")
        |> String.trim()
        |> title_verified?(criteria, identity)

      _no_scope_token ->
        false
    end
  end

  # A proven id makes the release's name irrelevant to identity; without
  # one the normalized title has to carry it.
  defp title_verified?(_parsed_title, %Criteria{}, :match), do: true

  defp title_verified?(parsed_title, %Criteria{} = criteria, _identity),
    do: title_matches?(parsed_title, criteria.title, criteria.origin_country)

  defp matches_criteria?(
         %Parser.Result{type: :tv} = parsed,
         %Criteria{tmdb_type: :tv} = criteria,
         identity
       ) do
    title_verified?(parsed.title, criteria, identity) and
      parsed.season == criteria.season_number and
      parsed.episode == criteria.episode_number
  end

  defp matches_criteria?(
         %Parser.Result{type: :movie} = parsed,
         %Criteria{tmdb_type: :movie} = criteria,
         :match
       ), do: title_verified?(parsed.title, criteria, :match)

  defp matches_criteria?(
         %Parser.Result{type: :movie} = parsed,
         %Criteria{tmdb_type: :movie} = criteria,
         _identity
       ) do
    title_matches?(parsed.title, criteria.title, criteria.origin_country) and
      year_matches?(parsed.year, criteria.year)
  end

  defp matches_criteria?(_parsed, _criteria, _identity), do: false

  defp title_matches?(parsed_title, expected_title, origin_countries)
       when is_binary(parsed_title) and is_binary(expected_title) do
    parsed = normalize(parsed_title)
    expected = normalize(expected_title)

    parsed == expected or origin_tagged_match?(parsed, expected, origin_countries)
  end

  defp title_matches?(_, _, _), do: false

  # `sample show us` matches `sample show` only when the show's TMDB
  # origin countries include the tag. Empty origins reject every tag —
  # without knowing the origin, a tagged release may be the same-title
  # remake from another country.
  defp origin_tagged_match?(parsed, expected, [_ | _] = origin_countries) do
    case String.split(parsed, " ") do
      [_, _ | _] = words ->
        {[tag], rest} = words |> Enum.reverse() |> Enum.split(1)

        Map.get(@country_tags, tag) in origin_countries and
          rest |> Enum.reverse() |> Enum.join(" ") == expected

      _single_word ->
        false
    end
  end

  defp origin_tagged_match?(_parsed, _expected, _origin_countries), do: false

  defp year_matches?(nil, _expected_year), do: true
  defp year_matches?(_parsed_year, nil), do: true

  # ±1: release names carry whichever year the group's source used —
  # festival premiere vs theatrical release routinely differ by one.
  defp year_matches?(parsed_year, expected_year), do: abs(parsed_year - expected_year) <= 1

  defp normalize(title) do
    title
    |> String.downcase()
    |> String.replace(~r/['']/u, "")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end
end
