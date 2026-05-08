defmodule MediaCentarr.Acquisition.DownloadClient.QBittorrent.Sync do
  @moduledoc """
  Pure delta application for qBittorrent's `sync/maindata` API.

  qBittorrent's RID-based incremental sync is built around a server-side
  conversation: the client sends a request ID, the server returns the
  changes since that ID. The client applies those changes to its local
  mirror, stores the new RID, and asks again. If the server's history
  doesn't reach back to the client's RID, the server returns
  `full_update: true` and the client replaces its mirror wholesale.

  This module is the pure side of that conversation — given a current
  torrent map and a parsed maindata response, it returns the next
  torrent map. No IO, no state.

  ## Shape of the torrent map

  Keys are torrent hashes; values are the raw qBittorrent maps as
  returned by the API. We keep the raw shape so `QueueItem.from_qbittorrent/1`
  can do its existing field translation without changes.

  Each value carries a `"hash"` key that mirrors its key in the outer
  map. qBittorrent does not always include the hash in the value of a
  partial update; we backfill it on insert so downstream consumers can
  treat each value as self-describing.
  """

  alias MediaCentarr.Acquisition.QueueItem

  @type torrent_map :: %{required(String.t()) => map()}

  @doc """
  Applies a parsed `sync/maindata` response to the current torrent map.
  Handles three cases: full update (replace), partial deltas (merge per
  hash), and removals (drop hashes listed in `torrents_removed`).
  """
  @spec apply_maindata(torrent_map(), map()) :: torrent_map()
  def apply_maindata(_current, %{"full_update" => true} = response) do
    response
    |> Map.get("torrents", %{})
    |> tag_with_hash()
  end

  def apply_maindata(current, response) do
    current
    |> apply_changes(Map.get(response, "torrents", %{}))
    |> apply_removals(Map.get(response, "torrents_removed", []))
  end

  defp apply_changes(current, changes) do
    Enum.reduce(changes, current, fn {hash, partial}, acc ->
      Map.update(
        acc,
        hash,
        Map.put(partial, "hash", hash),
        &Map.merge(&1, partial)
      )
    end)
  end

  defp apply_removals(current, hashes) do
    Map.drop(current, hashes)
  end

  defp tag_with_hash(torrents_map) do
    Map.new(torrents_map, fn {hash, raw} -> {hash, Map.put(raw, "hash", hash)} end)
  end

  @doc """
  Converts the internal torrent map to a list of `%QueueItem{}` for UI
  consumption. The translation lives in `QueueItem.from_qbittorrent/1`
  and is unchanged by the move to incremental sync.
  """
  @spec to_queue_items(torrent_map()) :: [QueueItem.t()]
  def to_queue_items(torrents) do
    torrents
    |> Map.values()
    |> Enum.map(&QueueItem.from_qbittorrent/1)
  end
end
