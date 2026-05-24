defmodule MediaCentaur.Acquisition.Pursuits.DownloadIdentity do
  @moduledoc """
  Captures the durable download→file link onto a pursuit's current
  target the first time its torrent is observed in the queue.

  The pursuit↔download pairing goes through the shared
  `QueueMatcher.find_item/4`. This callback only fires for targets that
  carry **no** `torrent_hash` yet (the guard below), so it always takes
  the matcher's title path (exact, then prefix-tolerant containment) —
  the *backfill* that captures the infohash for releases whose indexer
  never exposed one at grab time. On the first tick where the target's
  torrent is visible, its infohash (`QueueItem.id`) and on-disk
  `content_path` are written to the `Target` (write-once via
  `Target.record_download_changeset/2`); from then on every match is by
  hash and immune to tracker-prefixed names.

  Later stages resolve the pursuit's position in the lifecycle from that
  `content_path`, which the pipeline carries unchanged into review and
  the library — so the link survives the download client removing the
  completed torrent, where the title-only match in `QueueMatcher` dies.

  Invoked once per active pursuit per `Pursuits.Watcher` tick. A target
  that already carries a hash, an absent torrent, an `:unknown` queue, or
  a nil target are all no-ops.
  """

  alias MediaCentaur.Acquisition.{QueueMatcher, Target}
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Repo

  @spec capture!(Target.t() | nil, [QueueItem.t()] | :unknown, String.t() | nil) :: :ok
  def capture!(nil, _queue, _release_title), do: :ok
  def capture!(_target, :unknown, _release_title), do: :ok
  def capture!(_target, _queue, nil), do: :ok
  def capture!(%Target{torrent_hash: hash}, _queue, _release_title) when is_binary(hash), do: :ok

  def capture!(%Target{} = target, queue, release_title)
      when is_list(queue) and is_binary(release_title) do
    case QueueMatcher.find_item(queue, target.torrent_hash, release_title) do
      %QueueItem{} = item ->
        target
        |> Target.record_download_changeset(%{
          torrent_hash: item.id,
          content_path: item.content_path
        })
        |> Repo.update!()

        :ok

      nil ->
        :ok
    end
  end
end
