defmodule MediaCentaur.Repo.Migrations.AddWatcherFiles do
  use Ecto.Migration

  def change do
    # Create watcher_files table for filesystem presence tracking
    create table(:watcher_files, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :file_path, :text, null: false
      add :watch_dir, :text, null: false
      add :state, :text, null: false, default: "present"
      add :absent_since, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create unique_index(:watcher_files, [:file_path])
    create index(:watcher_files, [:watch_dir, :state])

    # Backfill watcher_files from existing library_watched_files
    execute(
      """
      INSERT INTO watcher_files (id, file_path, watch_dir, state, absent_since, inserted_at, updated_at)
      SELECT lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))),
             file_path, watch_dir,
             CASE WHEN state = 'complete' THEN 'present' ELSE 'absent' END,
             absent_since, inserted_at, updated_at
      FROM library_watched_files
      WHERE file_path IS NOT NULL AND watch_dir IS NOT NULL
      """,
      """
      DELETE FROM watcher_files
      """
    )

    # Drop the old composite index BEFORE removing columns (SQLite requirement).
    # Index was created on old `watched_files` table, so it retains the old name.
    drop_if_exists index(:watched_files, [:watch_dir, :state])

    # Remove presence-tracking columns from library_watched_files
    alter table(:library_watched_files) do
      remove :state, :text, default: "complete"
      remove :absent_since, :utc_datetime_usec
    end

    # Add a plain watch_dir index (no longer needs state)
    create index(:library_watched_files, [:watch_dir])
  end
end
