defmodule MediaCentarr.Repo.Migrations.AddDownloadIdentityToAcquisitionTargets do
  use Ecto.Migration

  # Persists the durable link from a target to the file its download
  # produced, so a pursuit can be tracked through the lifecycle stages
  # (downloaded → in review → landed in library) even after the download
  # client drops the completed torrent. Both nullable — populated on first
  # observation of the target's torrent in the queue.
  #
  # `torrent_hash` is qBittorrent's infohash (QueueItem.id); `content_path`
  # is the on-disk path the download lands at, which flows unchanged into
  # PendingFile.file_path / WatchedFile.file_path (the pipeline never
  # renames), making it an exact key for stage detection.
  def change do
    alter table(:acquisition_targets) do
      add :torrent_hash, :string
      add :content_path, :string
    end
  end
end
