defmodule MediaCentaur.TMDB.TitleSearch do
  @moduledoc """
  TMDB title search — the one normalized `[Title.t()]` every
  title-search surface consumes (omnibox, track flow).

  Plain queries go to the multi endpoint, preserving TMDB's cross-type
  relevance order (a regrouped movies-then-tv merge once starved every
  TV result out of the capped omnibox dropdown). Person results are
  dropped.

  A trailing year ("Title 1999", "Title (1999)") never matches a TMDB
  title through the multi endpoint, so it is stripped and sent as the
  year filter of the per-type search endpoints instead, merged by
  popularity. A year that filters everything out (wrong year, or a
  number that is part of the title) falls back to a year-less multi
  search of the stripped title — the year is a disambiguator, never a
  gatekeeper.

  Pure adapter: no persistence, no decoration. Surfaces layer tracked /
  watchlisted / in-library state on via ref sets.
  """

  alias MediaCentaur.TMDB.{Client, Title}

  require MediaCentaur.Log, as: Log

  # A query ending in a standalone year, optionally parenthesized
  # ("Title 1999", "Title (1999)"). The title part must be non-empty —
  # a bare year is a title query ("1999" the film), not a filter.
  @trailing_year_query ~r/^(.+?)\s+\(?((?:19|20)\d{2})\)?$/

  @spec search(String.t()) :: [Title.t()]
  def search(query) do
    case Regex.run(@trailing_year_query, String.trim(query)) do
      [_full, title, year] -> year_search(title, String.to_integer(year))
      nil -> multi_search(query)
    end
  end

  defp multi_search(query) do
    case Client.search_multi(query) do
      {:ok, results} -> Enum.flat_map(results, &normalize_multi_result/1)
      {:error, _reason} -> []
    end
  end

  # The per-type endpoints carry no cross-type relevance rank, so the
  # merged list orders by TMDB popularity instead.
  defp year_search(title, year) do
    movie_results = tag_media_type(Client.search_movie(title, year), "movie")
    tv_results = tag_media_type(Client.search_tv(title, year), "tv")

    case movie_results ++ tv_results do
      [] ->
        multi_search(title)

      combined ->
        combined
        |> Enum.sort_by(&(&1["popularity"] || 0.0), :desc)
        |> Enum.flat_map(&normalize_multi_result/1)
    end
  end

  defp tag_media_type({:ok, results}, media_type),
    do: Enum.map(results, &Map.put(&1, "media_type", media_type))

  defp tag_media_type({:error, _reason}, _media_type), do: []

  defp normalize_multi_result(%{"media_type" => "movie"} = tmdb), do: normalize(tmdb, :movie)
  defp normalize_multi_result(%{"media_type" => "tv"} = tmdb), do: normalize(tmdb, :tv_series)
  defp normalize_multi_result(_person_or_unknown), do: []

  # A TMDB hit missing its id or title is junk, not a crash: drop it and
  # keep the rest of the results. `Title.new!/1` stays the enforced
  # constructor for in-app builders, where a bad title is a programmer error.
  defp normalize(tmdb, media_type) do
    case Title.from_tmdb(tmdb, media_type) do
      {:ok, title} ->
        [title]

      {:error, changeset} ->
        Log.debug(
          :tmdb,
          "dropped malformed title hit #{inspect(tmdb["id"])}: #{inspect(changeset.errors)}"
        )

        []
    end
  end
end
