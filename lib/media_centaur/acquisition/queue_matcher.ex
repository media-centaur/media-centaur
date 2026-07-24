defmodule MediaCentaur.Acquisition.QueueMatcher do
  @moduledoc """
  Pairs pursuit rows with their currently-matched download-client queue
  items, **infohash-first**.

  The Downloads index renders pursuits with their live download nested
  inside each card. `@pursuit_rows` (DB-backed, refreshed on pursuit
  PubSub) and `@active_queue` (PubSub-backed, refreshed on every
  `QueueMonitor` snapshot) are independent assigns; `match/2` is a pure
  per-render helper that joins them without a DB roundtrip.

  ## Matching rule (`find_item/4` — the single shared predicate)

  1. **By infohash.** When the pursuit carries a `torrent_hash` (captured
     at grab time from the indexer, see
     `MediaCentaur.Acquisition.InfoHash`), match strictly against
     `QueueItem.id` (qBittorrent's infohash), case-insensitive. This is
     the durable key — immune to the tracker-prefixed names
     (`www.X.org - …`) that break title matching. An absent hash means
     the torrent has left the client, **not** that a same-titled stranger
     is it, so there is no title fallback in this branch.

  2. **By title, when no hash is known.** Normalized exact equality
     first; then *containment* — the release title appearing inside the
     torrent's (possibly prefixed) name — for titles long enough to be
     unambiguous. This keeps no-hash releases (usenet, indexers that omit
     the hash, pursuits grabbed before hashes were captured) pairing
     until `DownloadIdentity` backfills the hash from the observed queue
     item and matching becomes exact.

  Both `QueueItem.normalized_title` and `PursuitRow.normalized_release_title`
  are precomputed at construction time. On duplicate matches across rows,
  the first row in the input list claims the item — deterministic in
  `list_active_rows/0`'s `updated_at desc` order.
  """

  alias MediaCentaur.Acquisition.ViewModels.{DownloadProgress, PursuitRow, PursuitWithDownload}
  alias MediaCentaur.Downloads.QueueItem

  # A release title must normalize to at least this many characters before
  # the containment fallback will fire — short titles ("moviea") are too
  # collision-prone to match as a substring; they pair only on exact key.
  @min_contain_len 12

  @doc """
  Pairs rows with queue items.

  Returns `{paired, orphans}` where `paired` preserves the input row
  order with `download` and `queue_item_id` filled in when a match
  exists, and `orphans` is the list of queue items no row claimed.
  """
  @spec match([PursuitRow.t()], [QueueItem.t()]) ::
          {[PursuitWithDownload.t()], [QueueItem.t()]}
  def match(rows, queue) when is_list(rows) and is_list(queue) do
    {paired_rev, claimed} =
      Enum.reduce(rows, {[], MapSet.new()}, fn %PursuitRow{} = row, {acc, claimed} ->
        {downloads_rev, claimed} =
          row
          |> row_pairing_keys()
          |> Enum.reduce({[], claimed}, fn {hash, title}, {found, claimed} ->
            case find_item(queue, hash, title, claimed) do
              nil ->
                {found, claimed}

              item ->
                {[%{download: to_download(item), queue_item_id: item.id} | found], claim(claimed, item)}
            end
          end)

        downloads = Enum.reverse(downloads_rev)
        primary = List.first(downloads)

        entry = %PursuitWithDownload{
          row: row,
          download: primary && primary.download,
          queue_item_id: primary && primary.queue_item_id,
          downloads: downloads
        }

        {[entry | acc], claimed}
      end)

    orphans = Enum.reject(queue, fn %QueueItem{id: id} -> MapSet.member?(claimed, id) end)

    {Enum.reverse(paired_rev), orphans}
  end

  # Rows built before pairing_keys existed (or test fixtures) fall back
  # to the singular lead identity.
  defp row_pairing_keys(%PursuitRow{pairing_keys: [_ | _] = keys}), do: keys
  defp row_pairing_keys(%PursuitRow{torrent_hash: hash, release_title: title}), do: [{hash, title}]

  @doc """
  Finds the queue item identifying a pursuit — the single shared matcher
  used by the index pairing, status derivation, and identity capture.

  See the module doc for the infohash-first rule. `claimed` is a
  `MapSet` of queue-item ids already paired to an earlier row; matched
  items are skipped so each torrent pairs at most once.
  """
  @spec find_item([QueueItem.t()], String.t() | nil, String.t() | nil, MapSet.t()) ::
          QueueItem.t() | nil
  def find_item(queue, torrent_hash, release_title, claimed \\ MapSet.new())

  def find_item(queue, torrent_hash, _release_title, claimed)
      when is_binary(torrent_hash) and torrent_hash != "" do
    hash = String.downcase(torrent_hash)

    Enum.find(queue, fn %QueueItem{id: id} = item ->
      not claimed?(item, claimed) and is_binary(id) and String.downcase(id) == hash
    end)
  end

  def find_item(queue, _torrent_hash, release_title, claimed) do
    find_by_title(queue, release_title, claimed)
  end

  defp find_by_title(_queue, nil, _claimed), do: nil

  defp find_by_title(queue, release_title, claimed) do
    case normalize_title(release_title) do
      "" -> nil
      norm -> find_exact(queue, norm, claimed) || find_contained(queue, norm, claimed)
    end
  end

  defp find_exact(queue, norm, claimed) do
    Enum.find(queue, fn item -> not claimed?(item, claimed) and normalized_for(item) == norm end)
  end

  defp find_contained(queue, norm, claimed) when byte_size(norm) >= @min_contain_len do
    Enum.find(queue, fn item ->
      not claimed?(item, claimed) and String.contains?(normalized_for(item), norm)
    end)
  end

  defp find_contained(_queue, _norm, _claimed), do: nil

  defp claimed?(%QueueItem{id: id}, claimed), do: MapSet.member?(claimed, id)

  defp claim(claimed, nil), do: claimed
  defp claim(claimed, %QueueItem{id: id}), do: MapSet.put(claimed, id)

  # Falls back to on-the-fly normalisation when the cached value isn't
  # populated. Production paths (`QueueItem.from_qbittorrent/1`,
  # `Pursuits.list_rows/1`) fill the cache; test factories and future
  # drivers may leave it nil.
  defp normalized_for(%QueueItem{normalized_title: norm}) when is_binary(norm), do: norm
  defp normalized_for(%QueueItem{title: title}), do: normalize_title(title)

  @doc "Normalizes a title for matching. Delegates to `Pursuits.Identity` — the strategy owner."
  @spec normalize_title(String.t() | nil) :: String.t()
  defdelegate normalize_title(title), to: MediaCentaur.Acquisition.Pursuits.Identity

  @doc "Wraps a `QueueItem` into the `DownloadProgress` VM consumed by the row footer."
  @spec to_download(QueueItem.t() | nil) :: DownloadProgress.t() | nil
  def to_download(nil), do: nil

  # NZB-grab phase: SABnzbd is still fetching the .nzb from the indexer, so
  # its `percentage`/`timeleft` describe that tiny fetch, not the media.
  # Drop both — a bar that "starts at 19%" before content download begins
  # is exactly the misleading signal this state exists to avoid.
  def to_download(%QueueItem{state: :fetching_nzb} = qi) do
    %DownloadProgress{
      state: :fetching_nzb,
      progress_pct: nil,
      size_bytes: qi.size,
      size_left_bytes: qi.size_left,
      eta: nil,
      client: qi.download_client
    }
  end

  def to_download(%QueueItem{} = qi) do
    %DownloadProgress{
      state: qi.state,
      # `QueueItem.progress` is already a 0..100 percentage
      # (`QueueItem.from_qbittorrent` scales the qBittorrent 0..1 fraction
      # by 100), so it passes straight through. Re-multiplying here was the
      # cause of the "2330%" download in Active Pursuits.
      progress_pct: qi.progress,
      size_bytes: qi.size,
      size_left_bytes: qi.size_left,
      eta: qi.timeleft,
      client: qi.download_client
    }
  end
end
