defmodule MediaManager.TMDB.Client do
  @base_url "https://api.themoviedb.org/3"

  defp client do
    api_key = MediaManager.Config.get(:tmdb_api_key)
    Req.new(base_url: @base_url, params: [api_key: api_key])
  end

  @spec search_movie(String.t(), integer() | nil) :: {:ok, list(map())} | {:error, any()}
  def search_movie(title, year \\ nil) do
    params = [query: title] ++ if(year, do: [year: year], else: [])

    case Req.get(client(), url: "/search/movie", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body["results"] || []}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec search_tv(String.t(), integer() | nil) :: {:ok, list(map())} | {:error, any()}
  def search_tv(title, year \\ nil) do
    params = [query: title] ++ if(year, do: [first_air_date_year: year], else: [])

    case Req.get(client(), url: "/search/tv", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body["results"] || []}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_movie(String.t() | integer()) :: {:ok, map()} | {:error, any()}
  def get_movie(tmdb_id) do
    case Req.get(client(),
           url: "/movie/#{tmdb_id}",
           params: [append_to_response: "credits,release_dates,images"]
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_tv(String.t() | integer()) :: {:ok, map()} | {:error, any()}
  def get_tv(tmdb_id) do
    case Req.get(client(), url: "/tv/#{tmdb_id}", params: [append_to_response: "images"]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_season(String.t() | integer(), integer()) :: {:ok, map()} | {:error, any()}
  def get_season(tmdb_id, season_number) do
    case Req.get(client(), url: "/tv/#{tmdb_id}/season/#{season_number}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
