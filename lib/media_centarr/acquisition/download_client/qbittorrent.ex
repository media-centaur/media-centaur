defmodule MediaCentarr.Acquisition.DownloadClient.QBittorrent do
  @moduledoc """
  `DownloadClient` driver for the qBittorrent WebUI v2 API.

  qBittorrent docs: https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)

  ## Endpoints used

  | Operation | Method + path                  |
  |-----------|--------------------------------|
  | Login     | `POST /api/v2/auth/login`      |
  | List      | `GET  /api/v2/torrents/info`   |
  | Delete    | `POST /api/v2/torrents/delete` |
  | Version   | `GET  /api/v2/app/version`     |

  ## Auth

  qBittorrent uses cookie-based session auth:

    1. POST form-encoded `username` + `password` to `/api/v2/auth/login`.
    2. Server replies with `Set-Cookie: SID=...`.
    3. Subsequent requests include `Cookie: SID=...`.
    4. Cookies expire after the server's configured session timeout
       (default 1h) and surface as 403 on the next call. We re-auth
       and retry the original request once.

  Some users disable auth on localhost. In that case the first request
  succeeds without a cookie and we never call `/api/v2/auth/login`.

  ## Configuration

  Reads from `MediaCentarr.Config`:

    * `:download_client_url`      — e.g. `http://localhost:8080`
    * `:download_client_username` — qBit WebUI username (may be nil)
    * `:download_client_password` — qBit WebUI password (may be nil)

  The base HTTP client and the session cookie are cached in
  `:persistent_term`. Call `invalidate_client/0` after settings change.
  """

  @behaviour MediaCentarr.Acquisition.DownloadClient

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.QueueItem
  alias MediaCentarr.Config

  @impl true
  def list_downloads(filter \\ :all, client \\ default_client()) do
    attempt(client, fn c ->
      case Req.get(c, url: "/api/v2/torrents/info", params: [filter: qbit_filter(filter)]) do
        {:ok, %{status: 200, body: torrents}} when is_list(torrents) ->
          {:ok, Enum.map(torrents, &QueueItem.from_qbittorrent/1)}

        {:ok, %{status: 403, body: body}} ->
          {:error, {:http_error, 403, body}}

        {:ok, %{status: status, body: body}} ->
          Log.warning(
            :acquisition,
            "qbittorrent list_downloads failed — status=#{status} body=#{inspect(body)}"
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Log.warning(:acquisition, "qbittorrent list_downloads error — #{inspect(reason)}")
          {:error, reason}
      end
    end)
  end

  @impl true
  def cancel_download(id, client \\ default_client()) do
    attempt(client, fn c ->
      case Req.post(c,
             url: "/api/v2/torrents/delete",
             form: [hashes: id, deleteFiles: "true"]
           ) do
        {:ok, %{status: 200}} ->
          :ok

        {:ok, %{status: 403, body: body}} ->
          {:error, {:http_error, 403, body}}

        {:ok, %{status: status, body: body}} ->
          Log.warning(
            :acquisition,
            "qbittorrent cancel_download failed — status=#{status} body=#{inspect(body)}"
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Log.warning(:acquisition, "qbittorrent cancel_download error — #{inspect(reason)}")
          {:error, reason}
      end
    end)
  end

  @impl true
  def test_connection(client \\ default_client()) do
    attempt(client, fn c ->
      case Req.get(c, url: "/api/v2/app/version") do
        {:ok, %{status: 200}} -> :ok
        {:ok, %{status: 403}} -> {:error, {:http_error, 403}}
        {:ok, %{status: status}} -> {:error, {:http_error, status}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc "Clears the cached HTTP client and session cookie."
  def invalidate_client do
    :persistent_term.erase({__MODULE__, :client})
    :persistent_term.erase({__MODULE__, :cookie})
    :ok
  end

  @doc """
  Returns a Req client configured for qBittorrent. The base client is
  cached in `:persistent_term`; if a session cookie has been obtained,
  it is composed into the returned client at call time.
  """
  def default_client do
    base =
      case :persistent_term.get({__MODULE__, :client}, nil) do
        nil ->
          client = build_client()
          :persistent_term.put({__MODULE__, :client}, client)
          client

        client ->
          client
      end

    case :persistent_term.get({__MODULE__, :cookie}, nil) do
      nil -> base
      cookie -> Req.merge(base, headers: [{"cookie", cookie}])
    end
  end

  defp build_client do
    if Config.get(:showcase_mode) do
      Req.new(plug: &MediaCentarr.Showcase.Stubs.qbittorrent_plug/1, retry: false)
    else
      url = Config.get(:download_client_url)
      Req.new(base_url: url, retry: false)
    end
  end

  # Runs `fun.(client)`. On a 403 response, attempts to authenticate and
  # retries once with a fresh client carrying the new cookie.
  defp attempt(client, fun) do
    case fun.(client) do
      {:error, {:http_error, 403, _}} ->
        with {:ok, fresh} <- authenticate(client), do: fun.(fresh)

      {:error, {:http_error, 403}} ->
        with {:ok, fresh} <- authenticate(client), do: fun.(fresh)

      result ->
        result
    end
  end

  defp authenticate(client) do
    username = Config.get(:download_client_username) || ""
    password = MediaCentarr.Secret.expose(Config.get(:download_client_password)) || ""

    Log.info(:acquisition, "qbittorrent — authenticating")

    case Req.post(client,
           url: "/api/v2/auth/login",
           form: [username: username, password: password]
         ) do
      {:ok, %{status: 200} = resp} ->
        case extract_sid(resp) do
          nil ->
            Log.warning(:acquisition, "qbittorrent — login returned 200 but no SID cookie")
            {:error, :auth_failed}

          cookie ->
            :persistent_term.put({__MODULE__, :cookie}, cookie)
            {:ok, Req.merge(client, headers: [{"cookie", cookie}])}
        end

      {:ok, %{status: 403}} ->
        Log.warning(:acquisition, "qbittorrent — auth failed (bad credentials)")
        {:error, :auth_failed}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:acquisition, "qbittorrent — auth error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_sid(resp) do
    resp
    |> Req.Response.get_header("set-cookie")
    |> Enum.find_value(fn cookie ->
      case Regex.run(~r/SID=([^;]+)/, cookie) do
        [_, sid] -> "SID=#{sid}"
        _ -> nil
      end
    end)
  end

  defp qbit_filter(:active), do: "active"
  defp qbit_filter(:completed), do: "completed"
  defp qbit_filter(:all), do: "all"
end
