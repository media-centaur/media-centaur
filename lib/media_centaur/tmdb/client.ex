defmodule MediaCentaur.TMDB.Client do
  @moduledoc """
  HTTP client for the TMDB (The Movie Database) API v3.

  Provides search and detail-fetch endpoints for movies, TV series,
  seasons, and collections. The `Req` client is built from the
  configured key on every call through `MediaCentaur.HttpClient.new/2`,
  which attaches the response cache and the instrumentation, and
  `MediaCentaur.TMDB.RateLimiter` adds its request step after them so a
  cache hit never spends a rate-limit slot.

  ## API Details

  - **Base URL:** `https://api.themoviedb.org/3`
  - **Auth:** v3 `api_key` query parameter on every request (left out of
    the cache key)
  - **Search endpoints:** `/search/movie`, `/search/tv`, `/search/multi`
  - **Detail endpoints:** `/movie/{id}`, `/tv/{id}`, `/tv/{id}/season/{n}`, `/collection/{id}`
  - **Image URL:** `https://image.tmdb.org/t/p/original{path}`

  ## Options

  Every public function takes a trailing keyword list:

    * `:client` — a `Req.Request` to use instead of `default_client/0`
      (tests and one-shot seeders).
    * `:reload` — `true` to fetch past a fresh cache entry and overwrite
      it. The release-tracking refresher uses this: TMDB marks details
      fresh for about eight hours, longer than its refresh interval.

  `configuration/1` always reloads; it exists to prove the key against
  the network.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.HttpClient
  alias MediaCentaur.TMDB.RateLimiter

  @base_url "https://api.themoviedb.org/3"

  @type opts :: [client: Req.Request.t(), reload: boolean()]

  @doc """
  True when a client error means the configured API key was rejected
  (HTTP 401/403) rather than a transient failure — callers route these
  to a `Log.error` naming Settings → TMDB, since no retry will fix them.
  """
  @spec auth_failure?(term()) :: boolean()
  def auth_failure?({:http_error, status, _}) when status in [401, 403], do: true
  def auth_failure?(_), do: false

  @doc """
  A `Req` client for the TMDB API, built from the configured key on every
  call so a saved key is live immediately.
  """
  @spec default_client() :: Req.Request.t()
  def default_client do
    api_key = MediaCentaur.Secret.expose(MediaCentaur.Settings.Config.get(:tmdb_api_key))

    __MODULE__
    |> HttpClient.new(
      upstream: :tmdb,
      base_url: @base_url,
      params: [api_key: api_key],
      cache: [exclude_params: ["api_key"]]
    )
    |> RateLimiter.attach()
  end

  @doc """
  Hits TMDB's `/3/configuration` endpoint — the canonical cheap
  credential check. The endpoint returns static image-CDN metadata, so
  a 200 response proves the api_key is accepted without consuming a
  useful quota slot or touching user data. Never served from the cache.
  """
  @spec configuration(opts()) :: {:ok, map()} | {:error, any()}
  def configuration(opts \\ []) do
    get(Keyword.put(opts, :reload, true), url: "/configuration")
  end

  @spec search_movie(String.t(), integer() | nil, opts()) :: {:ok, list(map())} | {:error, any()}
  def search_movie(title, year \\ nil, opts \\ []) do
    params = [query: title] ++ if(year, do: [year: year], else: [])
    Log.info(:tmdb, "searched movies — #{title}#{if year, do: " (#{year})", else: ""}")

    with {:ok, body} <- get(opts, url: "/search/movie", params: params) do
      results = body["results"] || []
      Log.info(:tmdb, "found #{length(results)} movie results")
      {:ok, results}
    end
  end

  @spec search_tv(String.t(), integer() | nil, opts()) :: {:ok, list(map())} | {:error, any()}
  def search_tv(title, year \\ nil, opts \\ []) do
    params = [query: title] ++ if(year, do: [first_air_date_year: year], else: [])
    Log.info(:tmdb, "searched TV — #{title}#{if year, do: " (#{year})", else: ""}")

    with {:ok, body} <- get(opts, url: "/search/tv", params: params) do
      results = body["results"] || []
      Log.info(:tmdb, "found #{length(results)} TV results")
      {:ok, results}
    end
  end

  @doc """
  Searches movies and TV together, ranked by TMDB's cross-type
  relevance. Results carry a `"media_type"` discriminator
  (`"movie"` / `"tv"` / `"person"`); callers filter what they want.
  No year filter — the multi endpoint doesn't support one.
  """
  @spec search_multi(String.t(), opts()) :: {:ok, list(map())} | {:error, any()}
  def search_multi(title, opts \\ []) do
    Log.info(:tmdb, "searched media — #{title}")

    with {:ok, body} <- get(opts, url: "/search/multi", params: [query: title]) do
      results = body["results"] || []
      Log.info(:tmdb, "found #{length(results)} media results")
      {:ok, results}
    end
  end

  @spec get_movie(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_movie(tmdb_id, opts \\ []) do
    Log.info(:tmdb, "fetched movie tmdb:#{tmdb_id}")

    get(opts,
      url: "/movie/#{tmdb_id}",
      params: [
        append_to_response: "credits,release_dates,images",
        include_image_language: "en,null"
      ]
    )
  end

  @spec get_tv(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_tv(tmdb_id, opts \\ []) do
    Log.info(:tmdb, "fetched TV tmdb:#{tmdb_id}")

    get(opts,
      url: "/tv/#{tmdb_id}",
      params: [
        append_to_response: "aggregate_credits,external_ids,images",
        include_image_language: "en,null"
      ]
    )
  end

  @spec get_collection(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_collection(collection_id, opts \\ []) do
    Log.info(:tmdb, "fetched collection tmdb:#{collection_id}")

    get(opts,
      url: "/collection/#{collection_id}",
      params: [append_to_response: "images", include_image_language: "en,null"]
    )
  end

  @spec get_season(String.t() | integer(), integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_season(tmdb_id, season_number, opts \\ []) do
    Log.info(:tmdb, "fetched season tmdb:#{tmdb_id} S#{season_number}")

    # `credits` rides along for per-episode cast membership: season
    # regulars come from the appended credits, guest stars ride on each
    # episode object (`Mapper.episode_attrs/2`).
    get(opts,
      url: "/tv/#{tmdb_id}/season/#{season_number}",
      params: [append_to_response: "credits"]
    )
  end

  defp get(opts, request) do
    {client, opts} = Keyword.pop_lazy(opts, :client, &default_client/0)

    case Req.get(client, request ++ opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
