defmodule MediaCentarr.Repo.Migrations.AddFilePresenceIdToLibraryFiles do
  use Ecto.Migration

  # Campaign: library-presence-unification, Phase 3 (schema).
  #
  # Adds the FK column `file_presence_id` to `library_watched_files` and
  # `library_extra_files` that references the new
  # `library_file_presences` table introduced in Phase 1. The column is
  # added as nullable here so the Phase-3 data migration can backfill
  # values from `file_path`; a follow-up migration tightens it to
  # `null: false` after backfill.
  #
  # `on_delete: :delete_all` enforces the core invariant of ADR-045:
  # a library entity cannot exist for a file the system hasn't observed.
  # Deleting a FilePresence (e.g. via the future AbsenceSweeper) cascades
  # to both the WatchedFile/ExtraFile row and — through their own cascades
  # — to dependent rows.

  def change do
    alter table(:library_watched_files) do
      add :file_presence_id,
          references(:library_file_presences, type: :uuid, on_delete: :delete_all)
    end

    alter table(:library_extra_files) do
      add :file_presence_id,
          references(:library_file_presences, type: :uuid, on_delete: :delete_all)
    end

    create index(:library_watched_files, [:file_presence_id])
    create index(:library_extra_files, [:file_presence_id])
  end
end
