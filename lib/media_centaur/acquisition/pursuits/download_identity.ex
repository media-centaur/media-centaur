defmodule MediaCentaur.Acquisition.Pursuits.DownloadIdentity do
  @moduledoc """
  Captures the durable download→file link onto a pursuit's current
  target the first time its torrent is observed in the queue.

  The pursuit↔download pairing goes through the shared
  `QueueMatcher.find_item/4`, which matches by infohash when the target
  already carries one (grab-time capture, v0.77.2) and otherwise by
  title (exact, then prefix-tolerant containment — the *backfill* that
  captures the infohash for releases whose indexer never exposed one at
  grab time). On the first tick where the target's torrent is visible,
  its infohash (`QueueItem.id`) and on-disk `content_path` are written to
  the `Target` (write-once via `Target.record_download_changeset/2`).

  The guard below gates on **`content_path`**, not `torrent_hash`. The
  `content_path` is the value this callback exists to capture — and it
  can only be read from the *live* download in the queue. Grab-time hash
  capture now populates `torrent_hash` before the download is ever seen,
  so gating on the hash would short-circuit before `content_path` is ever
  recorded, starving the `LibraryReconciler`'s authoritative path match
  and orphaning the pursuit on release-name drift. Gating on
  `content_path` lets the callback run for a hashed-but-unlanded target;
  the hash makes the pairing *stronger* (immune to tracker-prefixed
  names) rather than cancelling it.

  Later stages resolve the pursuit's position in the lifecycle from that
  `content_path`, which the pipeline carries unchanged into review and
  the library — so the link survives the download client removing the
  completed torrent, where the title-only match in `QueueMatcher` dies.

  Invoked once per active pursuit per `Pursuits.Watcher` tick. A target
  that already carries a `content_path`, an absent torrent, an `:unknown`
  queue, or a nil target are all no-ops.
  """

  alias MediaCentaur.Acquisition.{QueueMatcher, Target}
  alias MediaCentaur.Downloads.QueueItem
  alias MediaCentaur.Repo

  @spec capture!(Target.t() | nil, [QueueItem.t()] | :unknown, String.t() | nil) :: :ok
  def capture!(nil, _queue, _release_title), do: :ok
  def capture!(_target, :unknown, _release_title), do: :ok
  def capture!(_target, _queue, nil), do: :ok
  def capture!(%Target{content_path: path}, _queue, _release_title) when is_binary(path), do: :ok

  def capture!(%Target{} = target, queue, release_title)
      when is_list(queue) and is_binary(release_title) do
    case QueueMatcher.find_item(queue, target.torrent_hash, release_title) do
      %QueueItem{} = item ->
        target
        |> Target.record_download_changeset(%{
          torrent_hash: item.id,
          content_path: usable_content_path(item.content_path)
        })
        |> Repo.update!()

        :ok

      nil ->
        :ok
    end
  end

  # A dockerized client reports paths in its own mount namespace
  # (SABnzbd's history `storage`: /downloads/completed/…). Pinning a
  # path this host can't see poisons the write-once slot with a value
  # that can never match a library path — worse than nil, which leaves
  # the capture retrying until a real path (or the name-match landing
  # via InboundListener) arrives.
  defp usable_content_path(nil), do: nil

  defp usable_content_path(path) when is_binary(path) do
    if File.exists?(path), do: path
  end
end
