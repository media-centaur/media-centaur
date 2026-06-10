defmodule MediaCentaur.Downloads.DownloadClient.QBittorrent.Sync do
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

  alias MediaCentaur.Downloads.QueueItem

  defmodule State do
    @moduledoc """
    qBittorrent's opaque sync bookmark (`DownloadClient.driver_state`):
    the `rid` conversation id, the torrent mirror the deltas apply to,
    and the merged global `server_state`. Held by `QueueMonitor` between
    ticks but never inspected above the driver.
    """

    defstruct rid: 0, torrents: %{}, server_state: %{}

    @type t :: %__MODULE__{
            rid: non_neg_integer(),
            torrents: %{required(String.t()) => map()},
            server_state: map()
          }
  end

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

  @doc """
  Computes the display fields for one sync tick from a `sync/maindata`
  response and the before/after torrent maps. Movement detection
  (`movement?/1`) and the log summary both read from this single result
  so they can never drift. Pure.
  """
  @spec counts(map(), torrent_map(), torrent_map()) :: %{
          rid: integer(),
          full?: boolean(),
          total: non_neg_integer(),
          added: non_neg_integer(),
          changed: non_neg_integer(),
          removed: non_neg_integer()
        }
  def counts(response, before_torrents, after_torrents) do
    removed = response |> Map.get("torrents_removed", []) |> length()

    %{
      rid: Map.get(response, "rid", 0),
      full?: Map.get(response, "full_update", false),
      total: map_size(after_torrents),
      added: max(0, map_size(after_torrents) - map_size(before_torrents) + removed),
      changed: response |> Map.get("torrents", %{}) |> map_size(),
      removed: removed
    }
  end

  @doc """
  True when a sync tick reflects real queue movement — a torrent added
  or removed, or a partial delta carrying field changes. A `full_update`
  echo that merely repeats the prior set (`added: 0, removed: 0`) is NOT
  movement: its `changed` count is just the full snapshot size, not a
  delta, so it is ignored unless the update is partial.
  """
  @spec movement?(%{
          required(:full?) => boolean(),
          required(:added) => non_neg_integer(),
          required(:removed) => non_neg_integer(),
          required(:changed) => non_neg_integer()
        }) :: boolean()
  def movement?(%{full?: full?, added: added, removed: removed, changed: changed}) do
    added > 0 or removed > 0 or (not full? and changed > 0)
  end

  @doc "The qBittorrent-shaped log line body for one sync tick."
  @spec summary(map()) :: String.t()
  def summary(counts) do
    "queue sync — rid=#{counts.rid} full=#{counts.full?} torrents=#{counts.total} " <>
      "added=#{counts.added} changed=#{counts.changed} removed=#{counts.removed}"
  end
end
