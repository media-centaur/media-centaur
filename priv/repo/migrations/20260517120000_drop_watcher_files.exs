defmodule MediaCentarr.Repo.Migrations.DropWatcherFiles do
  use Ecto.Migration

  # Campaign: library-presence-unification, Phase 7.
  #
  # Drops the legacy `watcher_files` table now that `Library.FilePresence`
  # is the sole presence record (ADR-045). Phase 4 removed every Library
  # read of the table; Phase 5 moved pipeline dedup to ETS; Phase 6
  # moved TTL purge to `Library.AbsenceSweeper`. The dual-write into
  # this table was the last reason for it to exist, and Phase 7 deletes
  # both the writer (`Watcher.FilePresence`/`Watcher.KnownFile` modules)
  # and the table itself in the same commit.
  #
  # No reconcile pass is needed: the Phase-2 backfill skipped orphan
  # `:present` rows (they had no matching `library_watched_files`), and
  # any path that was still in flight at the time of the drop is
  # rediscovered by the next watcher scan because the watcher reads
  # known paths from `library_file_presences` post-Phase-7.

  def change do
    drop_if_exists table(:watcher_files)
  end
end
