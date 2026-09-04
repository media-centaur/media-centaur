defmodule MediaCentaur.Search.Prowlarr do
  @moduledoc """
  Release search and grab backed by the Prowlarr indexer aggregator API.

  Prowlarr API reference: https://prowlarr.com/docs/api/

  ## Endpoints used

  | Operation | Method + path           | Notes                              |
  |-----------|-------------------------|------------------------------------|
  | Search    | `GET  /api/v1/search`   | params: `query`, `type`, `year`    |
  | Grab      | `POST /api/v1/search`   | body: `{guid, indexerId}`          |

  ## Gotcha — grab is NOT `/api/v1/release`

  Sonarr and Radarr expose their grab endpoint at `POST /api/v1/release`.
  Prowlarr does not. Prowlarr's grab is `POST /api/v1/search` with the
  release as the JSON body. Posting to `/api/v1/release` returns HTTP 405
  Method Not Allowed. Easy mistake from muscle memory — don't repeat it.

  ## What Prowlarr does NOT expose

  Prowlarr is a search aggregator: once it forwards a grab to a download
  client, it has nothing more to say about that download. There is no
  `/api/v1/queue` endpoint. Active download progress lives on the
  download client itself (qBittorrent, Transmission, …) and is read
  through `MediaCentaur.Downloads.DownloadClient`.

  ## Configuration

  Reads from `MediaCentaur.Settings.Config`:

    * `:prowlarr_url`     — base URL, e.g. `http://localhost:9696`
    * `:prowlarr_api_key` — sent as `x-api-key` header

  The HTTP client is built from the current settings on every call, so a
  saved URL or key is live immediately.

  ## Testing

  Pass an explicit `client` argument to inject a `Req.Test` stub. Stubs
  MUST assert on `conn.method` and `conn.request_path` — earlier tests
  did not, which let the `/api/v1/release` bug ship.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Search.SearchResult

  @doc "A Req client for Prowlarr, built from the configured URL and key."
  def default_client, do: build_client()

  # Prowlarr's /api/v1/search fans out to every configured indexer in
  # real time. With 6+ indexers (especially when one is a meta-aggregator
  # like Knaben that does its own fan-out) the tail can run past 30s
  # even on a healthy host. The client default must survive that.
  # Lightweight calls (ping) override per-call when fast failure is
  # appropriate. Retries are off everywhere — if the user wants to
  # retry, they'll click again.
  @search_timeout_ms 60_000
  @ping_timeout_ms 5_000

  defp build_client do
    if Config.get(:showcase_mode) do
      Req.new(plug: &MediaCentaur.Showcase.Stubs.prowlarr_plug/1)
    else
      url = Config.get(:prowlarr_url)
      api_key = MediaCentaur.Secret.expose(Config.get(:prowlarr_api_key))

      # An unconfigured URL or key is left out rather than sent as nil; the
      # request then fails at the transport, and `Acquisition.available?/0`
      # keeps callers from getting this far in the first place.
      MediaCentaur.HttpClient.new(
        __MODULE__,
        [receive_timeout: @search_timeout_ms, retry: false] ++
          if(is_binary(url) and url != "", do: [base_url: url], else: []) ++
          if(api_key, do: [headers: [{"x-api-key", api_key}]], else: [])
      )
    end
  end

  @doc """
  Lightweight connectivity + auth probe. Hits `GET /api/v1/system/status`,
  which returns 200 immediately when the URL is reachable and the api key
  is valid. Used by the Settings → *Test connection* button — never call
  `search/2` for connectivity testing, since search performs a live
  indexer fan-out and can take 30s+ on a healthy host.
  """
  @spec ping(Req.Request.t()) :: :ok | {:error, term()}
  def ping(client \\ default_client()) do
    case Req.get(client, url: "/api/v1/system/status", receive_timeout: @ping_timeout_ms) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Log.warning(:acquisition, "prowlarr ping failed — status=#{status}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:acquisition, "prowlarr ping error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  def search(query, opts \\ [], client \\ default_client()) do
    params = [query: query, type: "search"] ++ maybe_year(opts)
    Log.info(:acquisition, "prowlarr search — #{query}")

    case Req.get(client, url: "/api/v1/search", params: params) do
      {:ok, %{status: 200, body: results}} when is_list(results) ->
        search_results = Enum.map(results, &SearchResult.from_prowlarr/1)
        Log.info(:acquisition, "prowlarr found #{length(search_results)} results for #{query}")
        {:ok, search_results}

      {:ok, %{status: status, body: body}} ->
        Log.warning(
          :acquisition,
          "prowlarr search failed — status=#{status} body=#{inspect(body)}"
        )

        {:error, {:http_error, status, body}}

      {:error, reason} ->
        # Req returned `{:error, _}` — the indexer was unreachable (timeout,
        # refused, DNS). That is transient external-dependency connectivity, not
        # an application fault, so it stays in the console but mints no `:log`
        # incident (`mc_incident: :skip`) — the same treatment as the download
        # client's connectivity. A persistent indexer *misconfiguration* surfaces
        # via the non-200 "prowlarr search failed — status=" path above, which
        # still mints.
        Log.warning(:acquisition, "prowlarr search error — #{inspect(reason)}", mc_incident: :skip)
        {:error, reason}
    end
  end

  def grab(result, client \\ default_client())

  def grab(%{indexer_id: nil} = result, _client) do
    # Prowlarr's /api/v1/search requires a non-null integer indexerId;
    # posting null returns an opaque .NET "could not be converted to
    # System.Int32" validation error. Refuse with a clear reason so the
    # caller degrades to seeking instead of logging that noise. Reaches here
    # for plan units assigned before assigned_indexer_id was persisted.
    Log.warning(:acquisition, "prowlarr grab skipped — missing indexer id — #{result.title}")
    {:error, :missing_indexer_id}
  end

  def grab(result, client) do
    Log.info(:acquisition, "prowlarr grab — #{result.title}")

    payload = %{"guid" => result.guid, "indexerId" => result.indexer_id}

    case Req.post(client, url: "/api/v1/search", json: payload) do
      {:ok, %{status: 200}} ->
        Log.info(:acquisition, "prowlarr grab submitted — #{result.title}")
        :ok

      {:ok, %{status: status, body: body}} ->
        Log.warning(:acquisition, "prowlarr grab failed — status=#{status} body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:acquisition, "prowlarr grab error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Snapshots the indexer roster and per-indexer back-off state — the raw
  material for `MediaCentaur.Search.IndexerHealth.classify/3`.

  Two reads: `GET /api/v1/indexer` (which indexers exist and are
  enabled) and `GET /api/v1/indexerstatus` (which are temporarily
  disabled after failures, and until when). Prowlarr reports a back-off
  as `disabledTill`; an entry can also carry `disabledTill: null` for a
  failure that didn't escalate — kept, and filtered by the classifier.
  """
  @spec indexer_snapshot(Req.Request.t()) ::
          {:ok, %{indexers: [map()], backoffs: [map()]}} | {:error, term()}
  def indexer_snapshot(client \\ default_client()) do
    with {:ok, indexers} <- get_list(client, "/api/v1/indexer"),
         {:ok, statuses} <- get_list(client, "/api/v1/indexerstatus") do
      {:ok,
       %{
         indexers:
           Enum.map(indexers, fn indexer ->
             %{id: indexer["id"], name: indexer["name"], enabled: indexer["enable"] == true}
           end),
         backoffs:
           Enum.map(statuses, fn status ->
             %{indexer_id: status["indexerId"], disabled_till: parse_datetime(status["disabledTill"])}
           end)
       }}
    end
  end

  defp get_list(client, path) do
    # Health probe — must fail fast like ping/1, never inherit the 60s
    # search budget: an unanswered roster read IS the unhealthy signal.
    case Req.get(client, url: path, receive_timeout: @ping_timeout_ms) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Log.warning(:acquisition, "prowlarr #{path} failed — status=#{status}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        # Same transient-connectivity treatment as search/2: console-visible,
        # but no `:log` incident — persistent unreachability surfaces through
        # the `:subsystem` track (Search.IncidentContext, ADR-054).
        Log.warning(:acquisition, "prowlarr #{path} error — #{inspect(reason)}", mc_incident: :skip)
        {:error, reason}
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  @doc """
  Lists download clients configured in Prowlarr.

  Returns a list of `%{name, type, url, username, enabled}` maps. The
  `type` is normalized to a lowercase string suitable for the
  `:download_client_type` config key. Passwords are NOT returned —
  Prowlarr deliberately omits them from the API for security.

  Used by the Settings UI's "Detect from Prowlarr" button to pre-fill
  the download client form.
  """
  @spec list_download_clients(Req.Request.t()) :: {:ok, [map()]} | {:error, term()}
  def list_download_clients(client \\ default_client()) do
    case Req.get(client, url: "/api/v1/downloadclient") do
      {:ok, %{status: 200, body: clients}} when is_list(clients) ->
        {:ok, Enum.map(clients, &parse_download_client/1)}

      {:ok, %{status: status, body: body}} ->
        Log.warning(
          :acquisition,
          "prowlarr list_download_clients failed — status=#{status} body=#{inspect(body)}"
        )

        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:acquisition, "prowlarr list_download_clients error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_download_client(raw) do
    fields = field_map(raw["fields"])

    host = fields["host"]
    port = fields["port"]
    use_ssl = fields["useSsl"] == true
    scheme = if use_ssl, do: "https", else: "http"

    %{
      name: raw["name"],
      type: normalize_type(raw["implementation"]),
      url: build_url(scheme, host, port),
      username: blank_to_nil(fields["username"]),
      enabled: raw["enable"] == true
    }
  end

  # Prowlarr returns each field as `%{"name" => name, "value" => value, ...}`,
  # but optional fields that are unset come back without the `"value"` key
  # (only "name", "label", "type", etc.). Tolerate the absence.
  defp field_map(fields) when is_list(fields) do
    for %{"name" => name} = field <- fields, into: %{}, do: {name, field["value"]}
  end

  defp field_map(_), do: %{}

  defp build_url(_scheme, nil, _), do: nil
  defp build_url(scheme, host, nil), do: "#{scheme}://#{host}"
  defp build_url(scheme, host, port), do: "#{scheme}://#{host}:#{port}"

  defp normalize_type(nil), do: nil
  defp normalize_type("QBittorrent"), do: "qbittorrent"

  defp normalize_type(implementation) when is_binary(implementation), do: String.downcase(implementation)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_year(opts) do
    case Keyword.get(opts, :year) do
      nil -> []
      year -> [year: year]
    end
  end
end
