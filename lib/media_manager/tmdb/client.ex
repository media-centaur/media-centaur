defmodule MediaManager.TMDB.Client do
  @moduledoc """
  HTTP client for the TMDB (The Movie Database) API v3.

  Provides search and detail-fetch endpoints for movies, TV series, and seasons.
  Uses `Req` with a cached base client stored in `:persistent_term` to avoid
  reconstructing the request pipeline on every call.

  ## API Details

  - **Base URL:** `https://api.themoviedb.org/3`
  - **Auth:** v3 `api_key` query parameter on every request
  - **Search endpoints:** `/search/movie`, `/search/tv`
  - **Detail endpoints:** `/movie/{id}`, `/tv/{id}`, `/tv/{id}/season/{n}`, `/collection/{id}`
  - **Image URL:** `https://image.tmdb.org/t/p/original{path}`

  Each public function accepts an optional `Req.Request` argument for testability.
  """

  require MediaManager.Log, as: Log

  @base_url "https://api.themoviedb.org/3"

  @doc """
  Returns a `Req` client configured with the TMDB base URL and API key.
  Caches the client in `persistent_term` for reuse across calls.
  """
  def default_client do
    case :persistent_term.get({__MODULE__, :client}, nil) do
      nil ->
        client = build_client()
        :persistent_term.put({__MODULE__, :client}, client)
        client

      client ->
        client
    end
  end

  defp build_client do
    api_key = MediaManager.Config.get(:tmdb_api_key)
    Req.new(base_url: @base_url, params: [api_key: api_key])
  end

  @spec search_movie(String.t(), integer() | nil, Req.Request.t()) ::
          {:ok, list(map())} | {:error, any()}
  def search_movie(title, year \\ nil, client \\ default_client()) do
    params = [query: title] ++ if(year, do: [year: year], else: [])
    Log.info(:tmdb, "search movie: #{inspect(title)}, year: #{inspect(year)}")

    with {:ok, body} <- get(client, url: "/search/movie", params: params) do
      results = body["results"] || []
      Log.info(:tmdb, "search movie: #{length(results)} results")
      {:ok, results}
    end
  end

  @spec search_tv(String.t(), integer() | nil, Req.Request.t()) ::
          {:ok, list(map())} | {:error, any()}
  def search_tv(title, year \\ nil, client \\ default_client()) do
    params = [query: title] ++ if(year, do: [first_air_date_year: year], else: [])
    Log.info(:tmdb, "search tv: #{inspect(title)}, year: #{inspect(year)}")

    with {:ok, body} <- get(client, url: "/search/tv", params: params) do
      results = body["results"] || []
      Log.info(:tmdb, "search tv: #{length(results)} results")
      {:ok, results}
    end
  end

  @spec get_movie(String.t() | integer(), Req.Request.t()) :: {:ok, map()} | {:error, any()}
  def get_movie(tmdb_id, client \\ default_client()) do
    Log.info(:tmdb, "get movie tmdb:#{tmdb_id}")

    get(client,
      url: "/movie/#{tmdb_id}",
      params: [append_to_response: "credits,release_dates,images"]
    )
  end

  @spec get_tv(String.t() | integer(), Req.Request.t()) :: {:ok, map()} | {:error, any()}
  def get_tv(tmdb_id, client \\ default_client()) do
    Log.info(:tmdb, "get tv tmdb:#{tmdb_id}")
    get(client, url: "/tv/#{tmdb_id}", params: [append_to_response: "images"])
  end

  @spec get_collection(String.t() | integer(), Req.Request.t()) :: {:ok, map()} | {:error, any()}
  def get_collection(collection_id, client \\ default_client()) do
    Log.info(:tmdb, "get collection tmdb:#{collection_id}")
    get(client, url: "/collection/#{collection_id}", params: [append_to_response: "images"])
  end

  @spec get_season(String.t() | integer(), integer(), Req.Request.t()) ::
          {:ok, map()} | {:error, any()}
  def get_season(tmdb_id, season_number, client \\ default_client()) do
    Log.info(:tmdb, "get season tmdb:#{tmdb_id} S#{season_number}")
    get(client, url: "/tv/#{tmdb_id}/season/#{season_number}")
  end

  defp get(client, opts) do
    MediaManager.TMDB.RateLimiter.wait()

    case Req.get(client, opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
