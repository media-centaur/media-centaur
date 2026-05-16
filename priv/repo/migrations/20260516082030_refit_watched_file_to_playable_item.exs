defmodule MediaCentarr.Repo.Migrations.RefitWatchedFileToPlayableItem do
  @moduledoc """
  Library Schema v2 — Phase 2 Task B.

  Collapses the four-FK polymorphism on `library_watched_files`
  (`movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id`)
  into a single foreign key `playable_item_id` pointing at
  `library_playable_items`. The four old columns and the
  `WatchedFile.owner_id/1` coalescer disappear.

  This migration also introduces the new `library_extra_files` table —
  the file-presence side of `Library.Extra`. Paired here (rather than a
  separate migration) because the WatchedFile refit *creates* the rows
  that populate it: pre-existing `movie_series_id` WatchedFiles that
  point at collection-level Extras are moved into the new table rather
  than deleted as orphans.

  ## Sequence

  1. **Create `library_extra_files`** — the new file-presence table for
     `Library.Extra`. Unique on `file_path`, mirroring WatchedFile
     semantics.
  2. **Add** nullable `playable_item_id` column on
     `library_watched_files` with an FK to `library_playable_items`
     (`on_delete: :delete_all`).
  3. **Backfill** in four passes — one per legacy FK kind — each pass
     INSERTs the matching PlayableItem rows (when missing) and UPDATEs
     the WatchedFile to point at them:

     - `movie_id` set → `PlayableItem(:movie, movie_id, position: 1)`.
     - `video_object_id` set →
       `PlayableItem(:video_object, video_object_id, position: 1)`.
     - `tv_series_id` set → the WatchedFile is for an Episode under
       that series. The Episode is identified by
       `library_episodes.content_url == library_watched_files.file_path`.
       PlayableItem becomes `(:episode, episode.id, position: episode_number)`.
     - `movie_series_id` set → the WatchedFile is for a child Movie of
       the collection. The Movie is identified by
       `library_movies.content_url == library_watched_files.file_path
        AND library_movies.movie_series_id == watched_file.movie_series_id`.
       PlayableItem becomes `(:movie, movie.id, position: 1)`.

     SQLite has no native UUID function — UUID-v4 strings are
     synthesised via `randomblob` in the same shape as
     `20260515222530_restore_external_ids_as_sole_tmdb_imdb_source`.

  4. **Promote orphan-Extras into `library_extra_files`.** After step 3,
     the only orphan WatchedFiles left are the `movie_series_id` rows
     that don't have a child Movie matching `(content_url,
     movie_series_id)` — these are collection-level Extras (bonus
     features attached at the MovieSeries level). Match them against
     `library_extras` by `(content_url, movie_series_id)` and INSERT
     into `library_extra_files`. A production data audit found 22 such
     rows; preserving them is why this migration paired the new table
     in.

  5. **Delete remaining orphan** WatchedFile rows the backfill couldn't
     link to anything (neither PlayableItem nor Extra). Surviving
     orphans are dangling rows whose entity was deleted out from under
     them; dropping them is the lean cleanup the campaign authorises.
     A count is surfaced via `Logger.info/1`.

  6. **Drop** the four legacy FK columns and **promote**
     `playable_item_id` to `NOT NULL`. Index it for fast
     `EntityCascade` / `FileEventHandler` lookups.

  Not reversible — orphans are gone, columns are gone. The
  PlayableItem and ExtraFile rows the backfill created remain
  regardless.

  ## Why both schema and data here

  This is the paired schema+data migration carve-out from ADR-040: the
  UPDATEs and DELETEs MUST run between the column ADD and the column
  DROP, so they genuinely belong with the schema change. The
  `# credo:disable-next-line` comments on the mutating execute calls
  document the carve-out per MC0015.
  """
  use Ecto.Migration
  require Logger

  # UUID v4 string synthesised from `randomblob`. Re-used at multiple
  # backfill sites; defined once to keep them consistent.
  @uuid_v4 "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))"

  def up do
    # 1. Create the new `library_extra_files` table — file-presence side
    # of `Library.Extra`. Parallel to `library_watched_files` for
    # PlayableItems. Unique on `file_path` (one file ↔ one Extra).
    create table(:library_extra_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :file_path, :string, null: false
      add :watch_dir, :string

      add :extra_id,
          references(:library_extras, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create unique_index(:library_extra_files, [:file_path])
    create index(:library_extra_files, [:extra_id])

    # 2. Add nullable `playable_item_id`.
    alter table(:library_watched_files) do
      add :playable_item_id,
          references(:library_playable_items, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    # 3. Backfill — pass 1: standalone & collection-child movies.
    execute("""
    INSERT INTO library_playable_items (id, container_type, container_id, position, inserted_at, updated_at)
    SELECT DISTINCT
      #{@uuid_v4},
      'movie',
      wf.movie_id,
      1,
      datetime('now'),
      datetime('now')
    FROM library_watched_files wf
    WHERE wf.movie_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'movie'
           AND pi.container_id = wf.movie_id
           AND pi.position = 1
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watched_files
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              WHERE pi.container_type = 'movie'
                AND pi.container_id = library_watched_files.movie_id
                AND pi.position = 1
              LIMIT 1
           )
     WHERE movie_id IS NOT NULL AND playable_item_id IS NULL
    """)

    # Pass 2: video objects.
    execute("""
    INSERT INTO library_playable_items (id, container_type, container_id, position, inserted_at, updated_at)
    SELECT DISTINCT
      #{@uuid_v4},
      'video_object',
      wf.video_object_id,
      1,
      datetime('now'),
      datetime('now')
    FROM library_watched_files wf
    WHERE wf.video_object_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'video_object'
           AND pi.container_id = wf.video_object_id
           AND pi.position = 1
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watched_files
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              WHERE pi.container_type = 'video_object'
                AND pi.container_id = library_watched_files.video_object_id
                AND pi.position = 1
              LIMIT 1
           )
     WHERE video_object_id IS NOT NULL AND playable_item_id IS NULL
    """)

    # Pass 3: episodes (TV-series WatchedFiles resolved via
    # `library_episodes.content_url == library_watched_files.file_path`).
    execute("""
    INSERT INTO library_playable_items (id, container_type, container_id, position, inserted_at, updated_at)
    SELECT DISTINCT
      #{@uuid_v4},
      'episode',
      e.id,
      e.episode_number,
      datetime('now'),
      datetime('now')
    FROM library_watched_files wf
    JOIN library_episodes e ON e.content_url = wf.file_path
    WHERE wf.tv_series_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'episode'
           AND pi.container_id = e.id
           AND pi.position = e.episode_number
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watched_files
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              JOIN library_episodes e ON e.id = pi.container_id
             WHERE pi.container_type = 'episode'
               AND e.content_url = library_watched_files.file_path
             LIMIT 1
           )
     WHERE tv_series_id IS NOT NULL AND playable_item_id IS NULL
    """)

    # Pass 4: movie-series children (collection-child movies resolved
    # via `(content_url, movie_series_id)` join into `library_movies`).
    # In current production data this pass typically matches zero rows
    # because `20260515000000_repoint_collection_child_watched_files`
    # already moved well-formed child rows from `movie_series_id` to
    # `movie_id`. The leftover `movie_series_id` rows are Extras with
    # no Movie leaf — they are cleaned up as orphans below.
    execute("""
    INSERT INTO library_playable_items (id, container_type, container_id, position, inserted_at, updated_at)
    SELECT DISTINCT
      #{@uuid_v4},
      'movie',
      m.id,
      1,
      datetime('now'),
      datetime('now')
    FROM library_watched_files wf
    JOIN library_movies m
      ON m.content_url = wf.file_path
     AND m.movie_series_id = wf.movie_series_id
    WHERE wf.movie_series_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'movie'
           AND pi.container_id = m.id
           AND pi.position = 1
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watched_files
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              JOIN library_movies m ON m.id = pi.container_id
             WHERE pi.container_type = 'movie'
               AND m.content_url = library_watched_files.file_path
               AND m.movie_series_id = library_watched_files.movie_series_id
             LIMIT 1
           )
     WHERE movie_series_id IS NOT NULL AND playable_item_id IS NULL
    """)

    # 4. Promote orphan-Extras into `library_extra_files`. The only
    # remaining unlinked WatchedFiles at this point should be:
    #
    #   (a) `movie_series_id` rows pointing at collection-level Extras
    #       (file_path matches `library_extras.content_url` with
    #       matching `movie_series_id`) — these are preserved.
    #   (b) Truly dangling rows whose entity was deleted out from under
    #       them — these are dropped in step 5.
    #
    # The INSERT joins `library_extras` by `(content_url, movie_series_id)`.
    # Production data audit (2026-05-16) found 22 such Extras.
    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    INSERT INTO library_extra_files (id, file_path, watch_dir, extra_id, inserted_at, updated_at)
    SELECT
      #{@uuid_v4},
      wf.file_path,
      wf.watch_dir,
      x.id,
      datetime('now'),
      datetime('now')
    FROM library_watched_files wf
    JOIN library_extras x
      ON x.content_url = wf.file_path
     AND x.movie_series_id = wf.movie_series_id
    WHERE wf.playable_item_id IS NULL
      AND wf.movie_series_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_extra_files ef
         WHERE ef.file_path = wf.file_path
      )
    """)

    {:ok, %{rows: [[promoted_count]]}} =
      repo().query("""
      SELECT COUNT(*) FROM library_extra_files ef
       WHERE EXISTS (
         SELECT 1 FROM library_watched_files wf
          WHERE wf.file_path = ef.file_path
            AND wf.playable_item_id IS NULL
            AND wf.movie_series_id IS NOT NULL
       )
      """)

    if promoted_count > 0 do
      Logger.info(
        "refit_watched_file_to_playable_item — promoted #{promoted_count} orphan WatchedFile rows " <>
          "to library_extra_files (collection-level Extras)"
      )
    end

    # Now drop the promoted rows from WatchedFile so the only remaining
    # NULL-playable_item_id rows are truly dangling.
    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    DELETE FROM library_watched_files
     WHERE playable_item_id IS NULL
       AND file_path IN (SELECT file_path FROM library_extra_files)
    """)

    # 5. Drop remaining orphan WatchedFile rows that couldn't be linked
    # to anything. Logged so the operator sees the impact.
    {:ok, %{rows: [[orphan_count]]}} =
      repo().query("SELECT COUNT(*) FROM library_watched_files WHERE playable_item_id IS NULL")

    if orphan_count > 0 do
      Logger.info(
        "refit_watched_file_to_playable_item — deleting #{orphan_count} dangling WatchedFile rows " <>
          "(no PlayableItem and no Extra match)"
      )

      # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
      execute("DELETE FROM library_watched_files WHERE playable_item_id IS NULL")
    end

    # 6. Drop legacy FK columns and promote `playable_item_id` to NOT NULL.
    # SQLite can't ALTER COLUMN, so we do the standard table-rebuild
    # dance: create a new table with the target shape, copy the rows
    # (now all linked to PlayableItems), swap the tables.
    execute("PRAGMA foreign_keys = OFF")

    create table(:library_watched_files_new, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :file_path, :string, null: false
      add :watch_dir, :string

      add :playable_item_id,
          references(:library_playable_items, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    execute("""
    INSERT INTO library_watched_files_new
      (id, file_path, watch_dir, playable_item_id, inserted_at, updated_at)
    SELECT id, file_path, watch_dir, playable_item_id, inserted_at, updated_at
    FROM library_watched_files
    """)

    drop table(:library_watched_files)

    rename table(:library_watched_files_new), to: table(:library_watched_files)

    create index(:library_watched_files, [:playable_item_id])
    create unique_index(:library_watched_files, [:file_path])

    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    raise Ecto.MigrationError,
          "refit_watched_file_to_playable_item is not reversible — the four legacy FK columns " <>
            "were dropped and orphan WatchedFile rows were deleted destructively."
  end
end
