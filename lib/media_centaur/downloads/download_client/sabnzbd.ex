defmodule MediaCentaur.Downloads.DownloadClient.SABnzbd do
  @moduledoc """
  `DownloadClient` driver for the SABnzbd JSON API (usenet slot).

  SABnzbd docs: https://sabnzbd.org/wiki/advanced/api

  Every call is `GET {url}/api?output=json&apikey=KEY&mode=...`:

  | Operation       | Query                                            |
  |-----------------|--------------------------------------------------|
  | Live queue      | `mode=queue`                                     |
  | History window  | `mode=history&limit=30`                          |
  | Delete (queue)  | `mode=queue&name=delete&value=NZO_ID&del_files=1`|
  | Delete (history)| `mode=history&name=delete&value=NZO_ID&del_files=1`|
  | Connection test | `mode=queue&limit=1`                             |

  Delete is store-specific: a job is in the queue while active and in
  history once terminal (Completed/Failed). `cancel_download/2` tries the
  queue, then falls back to history when SABnzbd reports it removed
  nothing (`status: false`) — otherwise a failed job can never be
  deleted and re-renders on every poll.

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

  Every call takes the usenet slot's `MediaCentaur.Downloads.ClientConfig`
  (`url`, `api_key`); the driver reads no settings and caches nothing.
  """

  @behaviour MediaCentaur.Downloads.DownloadClient

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient.SyncResult
  alias MediaCentaur.Downloads.QueueItem

  # How many history entries each poll fetches. Covers the post-processing
  # pipeline plus enough completed/failed context for pursuit matching;
  # SABnzbd keeps history until the user clears it, so unbounded fetches
  # would grow every tick forever.
  @history_limit 30

  @impl true
  def test_connection(%ClientConfig{} = config) do
    case get_api(config, mode: "queue", limit: 1) do
      {:ok, _body} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def cancel_download(%ClientConfig{} = config, id) do
    # An NZO lives in exactly one store: the live queue while it's
    # grabbing/downloading/post-processing, or history once it's terminal
    # (Completed/Failed). Deletion is store-specific — the queue endpoint
    # silently no-ops (`status: false`) for a history id, which left failed
    # jobs undeletable and re-rendering on every poll. So attempt the queue
    # delete, and fall back to history when SABnzbd reports it removed
    # nothing. `del_files=1` removes the on-disk data in both stores.
    case delete_slot(config, "queue", id) do
      {:ok, %{"status" => false}} ->
        case delete_slot(config, "history", id) do
          {:ok, _body} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _body} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_slot(config, mode, id) do
    get_api(config, mode: mode, name: "delete", value: id, del_files: 1)
  end

  @impl true
  def sync(%ClientConfig{} = config, nil), do: sync(config, %{})

  def sync(%ClientConfig{} = config, previous_fingerprint) when is_map(previous_fingerprint) do
    with {:ok, queue_items} <- wrap_sync_error(fetch_queue_items(config), previous_fingerprint),
         {:ok, history_items} <-
           wrap_sync_error(fetch_history_items(config), previous_fingerprint) do
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

  # --- Internal ---

  defp fetch_queue_items(config) do
    with {:ok, body} <- get_api(config, mode: "queue") do
      slots = get_in(body, ["queue", "slots"]) || []
      {:ok, Enum.map(slots, &QueueItem.from_sabnzbd_queue/1)}
    end
  end

  defp fetch_history_items(config) do
    with {:ok, body} <- get_api(config, mode: "history", limit: @history_limit) do
      slots = get_in(body, ["history", "slots"]) || []
      {:ok, Enum.map(slots, &QueueItem.from_sabnzbd_history/1)}
    end
  end

  defp get_api(%ClientConfig{} = config, params) do
    client =
      MediaCentaur.HttpClient.new(__MODULE__, upstream: :sabnzbd, base_url: config.url, retry: false)

    api_key = MediaCentaur.Secret.expose(config.api_key) || ""
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
