defmodule MediaCentarr.Acquisition.Prowlarr do
  @moduledoc """
  `SearchProvider` implementation backed by the Prowlarr indexer aggregator API.

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
  through `MediaCentarr.Acquisition.DownloadClient`.

  ## Configuration

  Reads from `MediaCentarr.Config`:

    * `:prowlarr_url`     — base URL, e.g. `http://localhost:9696`
    * `:prowlarr_api_key` — sent as `x-api-key` header

  The HTTP client is built lazily, cached in `:persistent_term`, and
  rebuilt by `invalidate_client/0` (call after settings change).

  ## Testing

  Pass an explicit `client` argument to inject a `Req.Test` stub. Stubs
  MUST assert on `conn.method` and `conn.request_path` — earlier tests
  did not, which let the `/api/v1/release` bug ship.
  """

  @behaviour MediaCentarr.Acquisition.SearchProvider

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.SearchResult

  @doc "Clears the cached Req client so the next call rebuilds it from config."
  def invalidate_client do
    :persistent_term.erase({__MODULE__, :client})
    :ok
  end

  @doc "Returns a Req client configured for Prowlarr. Cached in `:persistent_term`."
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
    if MediaCentarr.Config.get(:showcase_mode) do
      Req.new(plug: &MediaCentarr.Showcase.Stubs.prowlarr_plug/1)
    else
      url = MediaCentarr.Config.get(:prowlarr_url)
      api_key = MediaCentarr.Secret.expose(MediaCentarr.Config.get(:prowlarr_api_key))
      Req.new(base_url: url, headers: [{"x-api-key", api_key}])
    end
  end

  @impl true
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
        Log.warning(:acquisition, "prowlarr search error — #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def grab(result, client \\ default_client()) do
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
