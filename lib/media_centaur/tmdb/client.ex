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
    * `:if_none_match` — `detail/2` only: the ETag the caller holds. The
      request carries it, the response cache stands aside, and a 304 is
      `{:ok, :unchanged}`. How `MediaCentaur.TMDB.Store` checks a stored
      title.

  `configuration/1` always reloads; it exists to prove the key against
  the network.

  ## Availability

  Every request's outcome is folded into `MediaCentaur.TMDB.Availability`
  — the `:tmdb` half of `MediaCentaur.IntegrationAvailability` — so the
  release-tracking refresh cycle and the artwork warm can ask whether
  TMDB can answer before spending a request on finding out. An answer
  served from the response cache reports nothing: it asked nobody.

  ## Write-through

  Transitional (campaign `tmdb-fetch-policy`, Phase 1): every detail
  payload `get_movie/2`, `get_tv/2` or `get_season/3` fetches is written
  to `MediaCentaur.TMDB.Store`, so the store fills while callers still
  fetch for themselves. A cache hit writes nothing. Removed when the last
  detail caller reads through the store.

  ## The console line

  Every answered call logs one line, after the fact, naming where the
  answer came from (`log_line/2`): `fetched movie tmdb:1317149 — from
  cache` for a table read, `— from TMDB` for a network call, and
  `— revalidated with TMDB` / `— refetched from TMDB` for the two other
  ways a request reaches the API, and `checked … — unchanged` when a
  `detail/2` check is answered 304. It used to log "fetched" before the
  request, so a hit and a miss read identically and a failure still
  claimed a fetch.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.HttpClient
  alias MediaCentaur.HttpClient.Cache
  alias MediaCentaur.TMDB.Availability
  alias MediaCentaur.TMDB.RateLimiter
  alias MediaCentaur.TMDB.Store

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
    get(Keyword.put(opts, :reload, true), [url: "/configuration"], "configuration")
  end

  @spec search_movie(String.t(), integer() | nil, opts()) :: {:ok, list(map())} | {:error, any()}
  def search_movie(title, year \\ nil, opts \\ []) do
    params = [query: normalize_query(title)] ++ if(year, do: [year: year], else: [])

    with {:ok, body} <-
           get(opts, [url: "/search/movie", params: params], "movies for #{query_words(title, year)}") do
      results = body["results"] || []
      Log.info(:tmdb, "found #{length(results)} movie results")
      {:ok, results}
    end
  end

  @spec search_tv(String.t(), integer() | nil, opts()) :: {:ok, list(map())} | {:error, any()}
  def search_tv(title, year \\ nil, opts \\ []) do
    params = [query: normalize_query(title)] ++ if(year, do: [first_air_date_year: year], else: [])

    with {:ok, body} <-
           get(opts, [url: "/search/tv", params: params], "TV for #{query_words(title, year)}") do
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
    with {:ok, body} <-
           get(
             opts,
             [url: "/search/multi", params: [query: normalize_query(title)]],
             "media for #{title}"
           ) do
      results = body["results"] || []
      Log.info(:tmdb, "found #{length(results)} media results")
      {:ok, results}
    end
  end

  @typedoc """
  What `detail/2` fetches: a title by the app's `{tmdb_id, media_type}`
  ref (`MediaCentaur.TMDB.Title.ref/1`), or one season.
  """
  @type detail_ref ::
          {pos_integer() | String.t(), :movie | :tv_series}
          | {:season, pos_integer() | String.t(), pos_integer()}

  @doc """
  One detail payload, with the ETag to revalidate it by — the request
  path `MediaCentaur.TMDB.Store` reads through. With `if_none_match:`
  the request carries the caller's validator, the response cache stands
  aside (`MediaCentaur.HttpClient.Cache`, `:conditional`), and a 304
  comes back as `{:ok, :unchanged}`. Without it, the request takes the
  cache's ordinary path. The `get_*` functions remain for callers that
  still fetch for themselves; they go as the store takes over.
  """
  @spec detail(detail_ref(), keyword()) ::
          {:ok, %{body: map(), etag: String.t() | nil}} | {:ok, :unchanged} | {:error, any()}
  def detail(ref, opts \\ []) do
    {etag, opts} = Keyword.pop(opts, :if_none_match)
    {client, opts} = Keyword.pop_lazy(opts, :client, &default_client/0)
    subject = detail_subject(ref)

    case Req.get(client, detail_request(ref) ++ conditional(etag) ++ opts) do
      {:ok, %{status: 200, body: body} = response} ->
        outcome = Cache.outcome(response)
        Availability.observe_request({:ok, outcome})
        Log.info(:tmdb, log_line(subject, outcome))
        {:ok, %{body: body, etag: etag(response)}}

      {:ok, %{status: 304} = response} ->
        Availability.observe_request({:ok, Cache.outcome(response)})
        # The store logs the check and its schedule at :info; this is the
        # transport fact beneath it.
        Log.debug(:tmdb, "checked #{subject} — unchanged")
        {:ok, :unchanged}

      {:ok, %{status: status, body: body}} ->
        Availability.observe_request({:error, {:http_error, status, body}})
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Availability.observe_request({:error, reason})
        {:error, reason}
    end
  end

  @spec get_movie(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_movie(tmdb_id, opts \\ []) do
    ref = {tmdb_id, :movie}
    get(opts, detail_request(ref), detail_subject(ref), ref)
  end

  @spec get_tv(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_tv(tmdb_id, opts \\ []) do
    ref = {tmdb_id, :tv_series}
    get(opts, detail_request(ref), detail_subject(ref), ref)
  end

  @spec get_collection(String.t() | integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_collection(collection_id, opts \\ []) do
    get(
      opts,
      [
        url: "/collection/#{collection_id}",
        params: [append_to_response: "images", include_image_language: "en,null"]
      ],
      "collection tmdb:#{collection_id}"
    )
  end

  @spec get_season(String.t() | integer(), integer(), opts()) :: {:ok, map()} | {:error, any()}
  def get_season(tmdb_id, season_number, opts \\ []) do
    ref = {:season, tmdb_id, season_number}
    get(opts, detail_request(ref), detail_subject(ref), ref)
  end

  defp detail_request({tmdb_id, :movie}) do
    [
      url: "/movie/#{tmdb_id}",
      params: [
        append_to_response: "credits,release_dates,images",
        include_image_language: "en,null"
      ]
    ]
  end

  defp detail_request({tmdb_id, :tv_series}) do
    [
      url: "/tv/#{tmdb_id}",
      params: [
        append_to_response: "aggregate_credits,external_ids,images",
        include_image_language: "en,null"
      ]
    ]
  end

  # `credits` rides along for per-episode cast membership: season
  # regulars come from the appended credits, guest stars ride on each
  # episode object (`Mapper.episode_attrs/2`).
  defp detail_request({:season, tmdb_id, season_number}) do
    [url: "/tv/#{tmdb_id}/season/#{season_number}", params: [append_to_response: "credits"]]
  end

  defp detail_subject({tmdb_id, :movie}), do: "movie tmdb:#{tmdb_id}"
  defp detail_subject({tmdb_id, :tv_series}), do: "TV tmdb:#{tmdb_id}"

  defp detail_subject({:season, tmdb_id, season_number}), do: "season tmdb:#{tmdb_id} S#{season_number}"

  defp conditional(nil), do: []
  defp conditional(etag), do: [headers: [{"if-none-match", etag}]]

  # Transitional (campaign tmdb-fetch-policy, Phase 1): every detail
  # payload a caller fetches is written to `TMDB.Store`, so the store
  # fills while callers still fetch for themselves. A cache hit writes
  # nothing — it asked nobody. Removed when the last detail caller reads
  # through the store.
  defp write_through(nil, _outcome, _body, _response), do: :ok
  defp write_through(_ref, :hit, _body, _response), do: :ok

  defp write_through({:season, tmdb_id, season_number} = ref, _outcome, body, response)
       when is_map(body) do
    tmdb_id
    |> Store.record_season_fetched(season_number, body, etag(response))
    |> note_write(ref)
  end

  defp write_through({_tmdb_id, _media_type} = ref, _outcome, body, response) when is_map(body) do
    ref
    |> Store.record_fetched(body, etag(response))
    |> note_write(ref)
  end

  defp write_through(_ref, _outcome, _body, _response), do: :ok

  # A store write never fails the fetch that triggered it: the caller
  # asked for a payload and has it.
  defp note_write({:ok, _record}, _ref), do: :ok

  defp note_write({:error, reason}, ref) do
    Log.debug(:tmdb, "store did not record #{detail_subject(ref)}: #{inspect(reason)}")
    :ok
  end

  defp etag(response), do: List.first(Req.Response.get_header(response, "etag"))

  @doc """
  The console line for a call that was answered: what was asked for, and
  where the answer came from.

  `subject` is the noun phrase the endpoint names itself with
  (`"movie tmdb:1317149"`, `"movies for Sample Show (2010)"`). The
  outcome is `MediaCentaur.HttpClient.Cache.outcome/1`; `:uncached`
  reads as a plain fetch, which is what it is for a client with no cache
  attached.
  """
  @spec log_line(String.t(), Cache.outcome()) :: String.t()
  def log_line(subject, outcome), do: "fetched #{subject} — #{source(outcome)}"

  defp source(:hit), do: "from cache"
  defp source(:revalidate), do: "revalidated with TMDB"
  defp source(:reload), do: "refetched from TMDB"
  # A 200 to the caller's own validator is a full fetch.
  defp source(_fetched), do: "from TMDB"

  defp query_words(title, nil), do: title
  defp query_words(title, year), do: "#{title} (#{year})"

  # TMDB's search is case-insensitive and whitespace-tolerant; the
  # response cache's key is not. One spelling per question. The console
  # line keeps the caller's spelling.
  defp normalize_query(title) do
    title |> String.trim() |> String.split() |> Enum.join(" ") |> String.downcase()
  end

  # Logged after the fact and only for an answered request: the outcome
  # is not known until the response is in hand, and a failure is the
  # caller's to report (`auth_failure?/1`) rather than something to
  # announce as a fetch.
  defp get(opts, request, subject, store_ref \\ nil) do
    {client, opts} = Keyword.pop_lazy(opts, :client, &default_client/0)

    case Req.get(client, request ++ opts) do
      {:ok, %{status: 200, body: body} = response} ->
        outcome = Cache.outcome(response)
        Availability.observe_request({:ok, outcome})
        Log.info(:tmdb, log_line(subject, outcome))
        write_through(store_ref, outcome, body, response)
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Availability.observe_request({:error, {:http_error, status, body}})
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Availability.observe_request({:error, reason})
        {:error, reason}
    end
  end
end
