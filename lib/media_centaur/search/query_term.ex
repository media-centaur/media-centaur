defmodule MediaCentaur.Search.QueryTerm do
  @moduledoc """
  Sanitizes constructed Prowlarr search terms.

  Scene release names never contain apostrophes (`Sample's Movie` is
  released as `Samples.Movie.2010…`), and indexer text search treats
  `I'm` and `Im` as different tokens — a TMDB title used verbatim as a
  query can return zero results for a title the indexer carries.
  Identity verification is unaffected (`TitleMatcher` strips
  apostrophes on both sides before comparing); only the outbound query
  needs the strip.

  Applies to constructed terms only (`Acquisition.Plans.LadderTerms`,
  `Search.QueryBuilder` tmdb variants). User-typed `manual_query`
  strings pass through verbatim — the user already trusts their query.

  Pure module — no I/O, no DB.
  """

  @spec sanitize(String.t()) :: String.t()
  def sanitize(title) do
    title
    |> String.replace(~r/['']/u, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
