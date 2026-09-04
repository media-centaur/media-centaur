defmodule MediaCentaur.Downloads.DownloadClient.QBittorrent do
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

  Every call takes the torrent slot's `MediaCentaur.Downloads.ClientConfig`
  (`url`, `username`, `password`); the driver reads no settings itself.
  Only the session cookie is kept between calls (`:persistent_term`) — a
  cookie the server no longer accepts surfaces as 403 and is replaced by
  a fresh login.
  """

  @behaviour MediaCentaur.Downloads.DownloadClient

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient.QBittorrent.Sync
  alias MediaCentaur.Downloads.DownloadClient.SyncResult

  @doc """
  Fetches incremental queue state via `/api/v2/sync/maindata?rid=N`.

  Pass `rid: 0` for the first call or after an error. The server
  returns `{"full_update": true, "torrents": {...}}` for a full
  snapshot or partial deltas otherwise. The response always carries a
  `"rid"` integer the caller must echo on the next request.

  This is qBittorrent's native incremental sync — the same mechanism
  the webUI uses, optimised for sub-second cadence with minimal
  bandwidth.
  """
  @spec sync_maindata(ClientConfig.t(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def sync_maindata(%ClientConfig{} = config, rid \\ 0) when is_integer(rid) and rid >= 0 do
    attempt(config, fn c ->
      case Req.get(c, url: "/api/v2/sync/maindata", params: [rid: rid]) do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          {:ok, body}

        {:ok, %{status: 403, body: body}} ->
          {:error, {:http_error, 403, body}}

        {:ok, %{status: status, body: body}} ->
          # Owned by Downloads.IncidentContext.assess/0 (the failed poll sets
          # QueueMonitor's last_error) — console-only, no duplicate :log incident
          # (ADR-054).
          Log.warning(
            :acquisition,
            "qbittorrent sync_maindata failed — status=#{status} body=#{inspect(body)}",
            mc_incident: :skip
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Log.warning(:acquisition, "qbittorrent sync_maindata error — #{inspect(reason)}",
            mc_incident: :skip
          )

          {:error, reason}
      end
    end)
  end

  @doc """
  One incremental-sync tick (`DownloadClient.sync/1`): wraps
  `sync_maindata/2` in the client-neutral contract. The opaque driver
  state is a `Sync.State` carrying the `rid` conversation and the
  torrent mirror; `nil` starts fresh with a full update.
  """
  @impl true
  def sync(%ClientConfig{} = config, nil), do: sync(config, %Sync.State{})

  def sync(%ClientConfig{} = config, %Sync.State{} = bookmark) do
    case sync_maindata(config, bookmark.rid) do
      {:ok, response} ->
        torrents = Sync.apply_maindata(bookmark.torrents, response)
        counts = Sync.counts(response, bookmark.torrents, torrents)

        next_bookmark = %Sync.State{
          rid: Map.get(response, "rid", bookmark.rid),
          torrents: torrents,
          server_state: Map.merge(bookmark.server_state, Map.get(response, "server_state", %{}))
        }

        {:ok,
         %SyncResult{
           items: Sync.to_queue_items(torrents),
           driver_state: next_bookmark,
           movement?: Sync.movement?(counts),
           summary: Sync.summary(counts)
         }}

      {:error, reason} ->
        # rid 0 forces a full update on the next successful poll — the
        # rid we have may be stale or the server may have lost it.
        {:error, reason, %{bookmark | rid: 0}}
    end
  end

  @impl true
  def cancel_download(%ClientConfig{} = config, id) do
    attempt(config, fn c ->
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
  def test_connection(%ClientConfig{} = config) do
    attempt(config, fn c ->
      case Req.get(c, url: "/api/v2/app/version") do
        {:ok, %{status: 200}} -> :ok
        {:ok, %{status: 403}} -> {:error, {:http_error, 403}}
        {:ok, %{status: status}} -> {:error, {:http_error, status}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  # The Req client for a slot: the configured base URL (or, in showcase
  # mode, the fixture plug) plus the session cookie when one is held.
  defp req(%ClientConfig{} = config) do
    base =
      if MediaCentaur.Settings.Config.get(:showcase_mode) do
        MediaCentaur.HttpClient.new(__MODULE__,
          upstream: :qbittorrent,
          plug: &MediaCentaur.Showcase.Stubs.qbittorrent_plug/1,
          retry: false
        )
      else
        MediaCentaur.HttpClient.new(__MODULE__,
          upstream: :qbittorrent,
          base_url: config.url,
          retry: false
        )
      end

    case :persistent_term.get({__MODULE__, :cookie}, nil) do
      nil -> base
      cookie -> Req.merge(base, headers: [{"cookie", cookie}])
    end
  end

  # Runs `fun.(req)`. On a 403 response, logs in with the slot's
  # credentials and retries once with a client carrying the new cookie.
  defp attempt(%ClientConfig{} = config, fun) do
    case fun.(req(config)) do
      {:error, {:http_error, 403, _}} ->
        with {:ok, fresh} <- authenticate(config), do: fun.(fresh)

      {:error, {:http_error, 403}} ->
        with {:ok, fresh} <- authenticate(config), do: fun.(fresh)

      result ->
        result
    end
  end

  defp authenticate(%ClientConfig{} = config) do
    client = req(config)
    username = config.username || ""
    password = MediaCentaur.Secret.expose(config.password) || ""

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
end
