defmodule MediaCentaur.TMDB.Client do
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

  require MediaCentaur.Log, as: Log

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
    api_key = MediaCentaur.Config.get(:tmdb_api_key)
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
      params: [
        append_to_response: "credits,release_dates,images",
        include_image_language: "en,null"
      ]
    )
  end

  @spec get_tv(String.t() | integer(), Req.Request.t()) :: {:ok, map()} | {:error, any()}
  def get_tv(tmdb_id, client \\ default_client()) do
    Log.info(:tmdb, "get tv tmdb:#{tmdb_id}")

    get(client,
      url: "/tv/#{tmdb_id}",
      params: [append_to_response: "images", include_image_language: "en,null"]
    )
  end

  @spec get_collection(String.t() | integer(), Req.Request.t()) :: {:ok, map()} | {:error, any()}
  def get_collection(collection_id, client \\ default_client()) do
    Log.info(:tmdb, "get collection tmdb:#{collection_id}")

    get(client,
      url: "/collection/#{collection_id}",
      params: [append_to_response: "images", include_image_language: "en,null"]
    )
  end

  @spec get_season(String.t() | integer(), integer(), Req.Request.t()) ::
          {:ok, map()} | {:error, any()}
  def get_season(tmdb_id, season_number, client \\ default_client()) do
    Log.info(:tmdb, "get season tmdb:#{tmdb_id} S#{season_number}")
    get(client, url: "/tv/#{tmdb_id}/season/#{season_number}")
  end

  defp get(client, opts) do
    endpoint = opts[:url] || "unknown"

    wait_start = System.monotonic_time()
    MediaCentaur.TMDB.RateLimiter.wait()
    wait_duration = System.monotonic_time() - wait_start

    :telemetry.execute(
      [:media_centaur, :tmdb, :rate_limit_wait],
      %{duration: wait_duration},
      %{endpoint: endpoint}
    )

    :telemetry.span([:media_centaur, :tmdb, :request], %{endpoint: endpoint}, fn ->
      case Req.get(client, opts) do
        {:ok, %{status: 200, body: body}} ->
          {{:ok, body}, %{status: 200}}

        {:ok, %{status: status, body: body}} ->
          {{:error, {:http_error, status, body}}, %{status: status}}

        {:error, reason} ->
          {{:error, reason}, %{error: reason}}
      end
    end)
  end
end
