defmodule MediaCentaur.Downloads.DownloadClient.SABnzbd do
  @moduledoc """
  `DownloadClient` driver for the SABnzbd JSON API (usenet slot).

  SABnzbd docs: https://sabnzbd.org/wiki/advanced/api

  Every call is `GET {url}/api?output=json&apikey=KEY&mode=...`:

  | Operation       | Query                                            |
  |-----------------|--------------------------------------------------|
  | Live queue      | `mode=queue`                                     |
  | History window  | `mode=history&limit=30`                          |
  | Delete          | `mode=queue&name=delete&value=NZO_ID&del_files=1`|
  | Connection test | `mode=queue&limit=1`                             |

  ## Auth

  API-key auth, key in every request. A rejected key comes back as
  **HTTP 200** with `{"status": false, "error": "API Key ..."}` — the
  error body is inspected so bad keys surface as `:auth_failed` (the
  same grade qBittorrent's cookie failures map to). The connection test
  deliberately uses the keyed `mode=queue` rather than the unkeyed
  `mode=version`, so "Test connection" actually validates the key.

  ## Sync (no delta API)

  Unlike qBittorrent's `rid` conversation, SABnzbd has no incremental
  sync: each `sync/1` tick fetches the full queue plus a bounded
  history window. The opaque driver state is a fingerprint of the last
  snapshot, used only to detect movement for log-cadence purposes.

  History matters because usenet completion happens there: a job leaves
  the live queue into par2-verify → repair → unrar, and only the
  history entry's `storage` path points at the final media file
  (`QueueItem.from_sabnzbd_history/1`).

  ## Configuration

  Reads from `MediaCentaur.Config`:

    * `:usenet_download_client_url`     — e.g. `http://localhost:8085`
    * `:usenet_download_client_api_key` — SABnzbd API key (Secret)

  The base HTTP client is cached in `:persistent_term`. Call
  `invalidate_client/0` after settings change.
  """

  @behaviour MediaCentaur.Downloads.DownloadClient

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Config
  alias MediaCentaur.Downloads.DownloadClient.SyncResult
  alias MediaCentaur.Downloads.QueueItem

  # How many history entries each poll fetches. Covers the post-processing
  # pipeline plus enough completed/failed context for pursuit matching;
  # SABnzbd keeps history until the user clears it, so unbounded fetches
  # would grow every tick forever.
  @history_limit 30

  @impl true
  def list_downloads(filter, client \\ default_client())

  def list_downloads(:active, client), do: fetch_queue_items(client)

  def list_downloads(:completed, client) do
    with {:ok, items} <- fetch_history_items(client) do
      {:ok, Enum.filter(items, &(&1.state == :completed))}
    end
  end

  def list_downloads(:all, client) do
    with {:ok, queue_items} <- fetch_queue_items(client),
         {:ok, history_items} <- fetch_history_items(client) do
      {:ok, queue_items ++ history_items}
    end
  end

  @impl true
  def test_connection(client \\ default_client()) do
    case get_api(client, mode: "queue", limit: 1) do
      {:ok, _body} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def cancel_download(id, client \\ default_client()) do
    case get_api(client, mode: "queue", name: "delete", value: id, del_files: 1) do
      {:ok, _body} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def sync(driver_state, client \\ default_client())
  def sync(nil, client), do: sync(%{}, client)

  def sync(previous_fingerprint, client) when is_map(previous_fingerprint) do
    with {:ok, queue_items} <- wrap_sync_error(fetch_queue_items(client), previous_fingerprint),
         {:ok, history_items} <-
           wrap_sync_error(fetch_history_items(client), previous_fingerprint) do
      items = queue_items ++ history_items
      fingerprint = fingerprint(items)

      {:ok,
       %SyncResult{
         items: items,
         driver_state: fingerprint,
         movement?: fingerprint != previous_fingerprint,
         summary: summary(items)
       }}
    end
  end

  @doc "Clears the cached HTTP client."
  def invalidate_client do
    :persistent_term.erase({__MODULE__, :client})
    :ok
  end

  @doc "Returns a Req client configured for SABnzbd, cached in `:persistent_term`."
  def default_client do
    case :persistent_term.get({__MODULE__, :client}, nil) do
      nil ->
        client = Req.new(base_url: Config.get(:usenet_download_client_url), retry: false)
        :persistent_term.put({__MODULE__, :client}, client)
        client

      client ->
        client
    end
  end

  # --- Internal ---

  defp fetch_queue_items(client) do
    with {:ok, body} <- get_api(client, mode: "queue") do
      slots = get_in(body, ["queue", "slots"]) || []
      {:ok, Enum.map(slots, &QueueItem.from_sabnzbd_queue/1)}
    end
  end

  defp fetch_history_items(client) do
    with {:ok, body} <- get_api(client, mode: "history", limit: @history_limit) do
      slots = get_in(body, ["history", "slots"]) || []
      {:ok, Enum.map(slots, &QueueItem.from_sabnzbd_history/1)}
    end
  end

  defp get_api(client, params) do
    api_key = MediaCentaur.Secret.expose(Config.get(:usenet_download_client_api_key)) || ""
    params = Keyword.merge([output: "json", apikey: api_key], params)

    case Req.get(client, url: "/api", params: params) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        classify_api_body(body)

      {:ok, %{status: status, body: body}} ->
        Log.warning(
          :acquisition,
          "sabnzbd request failed — mode=#{params[:mode]} status=#{status} body=#{inspect(body)}",
          mc_incident: :skip
        )

        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:acquisition, "sabnzbd request error — #{inspect(reason)}", mc_incident: :skip)
        {:error, reason}
    end
  end

  # SABnzbd reports API errors as HTTP 200 + {"status": false, "error": msg}.
  defp classify_api_body(%{"status" => false, "error" => message}) do
    if is_binary(message) and String.contains?(message, "API Key") do
      Log.warning(:acquisition, "sabnzbd — auth failed (#{message})", mc_incident: :skip)
      {:error, :auth_failed}
    else
      {:error, {:api_error, message}}
    end
  end

  defp classify_api_body(body), do: {:ok, body}

  defp wrap_sync_error({:ok, value}, _bookmark), do: {:ok, value}
  defp wrap_sync_error({:error, reason}, bookmark), do: {:error, reason, bookmark}

  # State + remaining bytes per id — enough to notice adds, removals,
  # state transitions, and download progress between ticks.
  defp fingerprint(items) do
    Map.new(items, fn item -> {item.id, {item.state, item.size_left}} end)
  end

  defp summary(items) do
    {queue_items, history_items} = Enum.split_with(items, &(&1.state not in [:completed, :error]))
    failed = Enum.count(history_items, &(&1.state == :error))

    "sabnzbd sync — active=#{length(queue_items)} " <>
      "completed=#{length(history_items) - failed} failed=#{failed}"
  end
end
