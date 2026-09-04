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
  alias MediaCentaur.DateUtil

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

  defp normalize_multi_result(%{"media_type" => "movie"} = tmdb), do: normalize_movie_result(tmdb)
  defp normalize_multi_result(%{"media_type" => "tv"} = tmdb), do: normalize_tv_result(tmdb)
  defp normalize_multi_result(_person_or_unknown), do: []

  defp normalize_movie_result(tmdb) do
    build_title(%{
      tmdb_id: tmdb["id"],
      media_type: :movie,
      name: tmdb["title"],
      year: DateUtil.extract_year(tmdb["release_date"]),
      release_date: extract_date(tmdb["release_date"]),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: tmdb["overview"]
    })
  end

  defp normalize_tv_result(tmdb) do
    build_title(%{
      tmdb_id: tmdb["id"],
      media_type: :tv_series,
      name: tmdb["name"],
      year: DateUtil.extract_year(tmdb["first_air_date"]),
      release_date: extract_date(tmdb["first_air_date"]),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: tmdb["overview"]
    })
  end

  # A TMDB hit missing its id or title is junk, not a crash: drop it and
  # keep the rest of the results. `Title.new!/1` stays the enforced
  # constructor for in-app builders, where a bad title is a programmer error.
  defp build_title(attrs) do
    case Ecto.Changeset.apply_action(Title.changeset(attrs), :insert) do
      {:ok, title} ->
        [title]

      {:error, changeset} ->
        Log.debug(
          :tmdb,
          "dropped malformed title hit #{inspect(attrs[:tmdb_id])}: #{inspect(changeset.errors)}"
        )

        []
    end
  end

  # Full date, not just the year — the results' upcoming/released scoping
  # compares against today. TMDB leaves unreleased titles undated or with
  # partial strings; both come through as nil.
  defp extract_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp extract_date(_missing), do: nil
end
