defmodule MediaCentaur.Review.Search do
  @moduledoc """
  Manual TMDB lookup for the review page's match picker — the user
  names the title the parser could not.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.DateUtil
  alias MediaCentaur.TMDB.Client

  @doc """
  Searches TMDB for a title the user typed into the match picker.
  Season/episode markers are stripped from the query first; results are
  normalised to the picker's `%{tmdb_id, title, year, overview,
  poster_path}` shape, ten at most.
  """
  @spec tmdb(String.t(), :tv | :movie) :: {:ok, [map()]} | {:error, term()}
  def tmdb(query, type) do
    Log.info(:review, "manual search — #{query} (#{type})")
    search_fn = if type == :tv, do: &Client.search_tv/2, else: &Client.search_movie/2
    title_key = if type == :tv, do: "name", else: "title"
    year_key = if type == :tv, do: "first_air_date", else: "release_date"
    cleaned_query = clean_search_query(query)

    case search_fn.(cleaned_query, nil) do
      {:ok, results} ->
        normalized =
          results
          |> Enum.take(10)
          |> Enum.map(fn result ->
            %{
              tmdb_id: to_string(result["id"]),
              title: result[title_key],
              year: DateUtil.extract_year(result[year_key]),
              overview: result["overview"],
              poster_path: result["poster_path"]
            }
          end)

        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clean_search_query(query) do
    query
    |> String.replace(~r/[Ss]\d{1,2}[Ee]\d{1,2}/, "")
    |> String.replace(~r/[Ss]eason\s*\d+/i, "")
    |> String.replace(~r/[Ee]pisode\s*\d+/i, "")
    |> String.replace(~r/[Ee]\d{2,}/, "")
    |> String.trim()
  end
end
