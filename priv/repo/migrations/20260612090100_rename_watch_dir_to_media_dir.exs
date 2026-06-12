defmodule MediaCentaur.Repo.Migrations.RenameWatchDirToMediaDir do
  @moduledoc """
  Renames the `watch_dir` columns to `media_dir` (and
  `review_pending_files.watch_directory` to `media_directory`) as part
  of the repository-wide "watch directory" → "media directory"
  terminology change. SQLite's RENAME COLUMN is metadata-only: instant,
  no table rewrite, and index/trigger references are rewritten
  automatically.

  Also pre-marks the two shipped data migrations whose raw SQL reads
  `watch_dir` (`BackfillFilePresences`, `BackfillFilePresenceIds`) as
  applied. Data migrations replay after ALL schema migrations on a
  fresh install, so without the marks they would crash against the
  renamed columns. Skipping them is semantically safe: a fresh database
  has no rows to backfill. Existing installs already carry both
  versions (healed into `data_migrations` by
  `HealDataMigrationsTracking`), so the `INSERT OR IGNORE` is a no-op
  there.
  """
  use Ecto.Migration

  @renamed_index "library_file_presences_watch_dir_last_seen_at_index"

  # The shipped data migrations whose SQL references watch_dir columns.
  @watch_dir_data_migrations [20_260_517_100_100, 20_260_517_110_200]

  def up do
    rename table(:library_watched_files), :watch_dir, to: :media_dir
    rename table(:library_extra_files), :watch_dir, to: :media_dir
    rename table(:library_file_presences), :watch_dir, to: :media_dir
    rename table(:pipeline_image_queue), :watch_dir, to: :media_dir
    rename table(:review_pending_files), :watch_directory, to: :media_directory

    # RENAME COLUMN already rewrote the index to point at media_dir but
    # kept the old name; recreate it so the name matches the column.
    drop index(:library_file_presences, [:media_dir, :last_seen_at], name: @renamed_index)
    create index(:library_file_presences, [:media_dir, :last_seen_at])

    versions =
      Enum.map_join(@watch_dir_data_migrations, ", ", fn version ->
        "(#{version}, '#{NaiveDateTime.to_iso8601(NaiveDateTime.utc_now(:second))}')"
      end)

    execute "INSERT OR IGNORE INTO data_migrations (version, inserted_at) VALUES #{versions}"
  end

  def down do
    drop index(:library_file_presences, [:media_dir, :last_seen_at])

    rename table(:library_watched_files), :media_dir, to: :watch_dir
    rename table(:library_extra_files), :media_dir, to: :watch_dir
    rename table(:library_file_presences), :media_dir, to: :watch_dir
    rename table(:pipeline_image_queue), :media_dir, to: :watch_dir
    rename table(:review_pending_files), :media_directory, to: :watch_directory

    create index(:library_file_presences, [:watch_dir, :last_seen_at], name: @renamed_index)

    # The data-migration marks stay: they are correct regardless of the
    # column names (the backfills' window has passed either way).
  end
end
