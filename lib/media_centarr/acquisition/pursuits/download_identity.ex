defmodule MediaCentarr.Acquisition.Pursuits.DownloadIdentity do
  @moduledoc """
  Captures the durable download→file link onto a pursuit's current
  target the first time its torrent is observed in the queue.

  The pursuit↔download pairing is by normalized title — the same key
  `QueueMatcher` uses for display, robust to separator differences
  between the picked release name and the torrent's name. On the first
  tick where the target's torrent is visible, its infohash
  (`QueueItem.id`) and on-disk `content_path` are written to the
  `Target` (write-once via `Target.record_download_changeset/2`).

  Later stages resolve the pursuit's position in the lifecycle from that
  `content_path`, which the pipeline carries unchanged into review and
  the library — so the link survives the download client removing the
  completed torrent, where the title-only match in `QueueMatcher` dies.

  Invoked once per active pursuit per `Pursuits.Watcher` tick. A target
  that already carries a hash, an absent torrent, an `:unknown` queue, or
  a nil target are all no-ops.
  """

  alias MediaCentarr.Acquisition.{QueueMatcher, Target}
  alias MediaCentarr.Downloads.QueueItem
  alias MediaCentarr.Repo

  @spec capture!(Target.t() | nil, [QueueItem.t()] | :unknown, String.t() | nil) :: :ok
  def capture!(nil, _queue, _release_title), do: :ok
  def capture!(_target, :unknown, _release_title), do: :ok
  def capture!(_target, _queue, nil), do: :ok
  def capture!(%Target{torrent_hash: hash}, _queue, _release_title) when is_binary(hash), do: :ok

  def capture!(%Target{} = target, queue, release_title)
      when is_list(queue) and is_binary(release_title) do
    case find_item(queue, release_title) do
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

  defp find_item(queue, release_title) do
    target_norm = QueueMatcher.normalize_title(release_title)
    Enum.find(queue, fn item -> normalized(item) == target_norm end)
  end

  defp normalized(%QueueItem{normalized_title: norm}) when is_binary(norm), do: norm
  defp normalized(%QueueItem{title: title}), do: QueueMatcher.normalize_title(title)
end
