defmodule MediaCentarr.Repo.Migrations.RefitWatchProgressToPlayableItem do
  @moduledoc """
  Library Schema v2 — Phase 2 Task C.

  Collapses the three-FK polymorphism on `library_watch_progress`
  (`movie_id`, `episode_id`, `video_object_id`) into a single foreign
  key `playable_item_id` pointing at `library_playable_items`. The
  three old columns disappear and a `UNIQUE(playable_item_id)`
  constraint enforces the campaign invariant "one progress row per
  playable item".

  ## Sequence

  1. **Add** nullable `playable_item_id` column on
     `library_watch_progress` with an FK to `library_playable_items`
     (`on_delete: :delete_all`).
  2. **Backfill** in three passes — one per legacy FK kind. Each pass
     INSERTs the matching PlayableItem rows (when missing) at
     `position = 1` for movie/video_object, or
     `position = episode_number` for episodes, and UPDATEs the
     WatchProgress to point at them.

     SQLite has no native UUID function — UUID-v4 strings are
     synthesised via `randomblob` in the same shape as Task B.

  3. **Dedupe** any leftover groups of WatchProgress rows that now
     point at the same `playable_item_id` (would violate the unique
     constraint added in step 5). Keep the most-recent-by
     `last_watched_at` row per group, delete the rest. In dev +
     showcase the table is empty; this pass is defensive against
     production data drift.

  4. **Delete remaining orphan** WatchProgress rows that couldn't be
     linked to anything — their leaf entity was deleted out from under
     them. Surface a `Logger.info/1` count.

  5. **Drop** the three legacy FK columns, promote `playable_item_id`
     to `NOT NULL`, and create `UNIQUE(playable_item_id)`. SQLite
     can't ALTER COLUMN, so the standard rebuild dance: create
     `library_watch_progress_new` with the target shape, copy rows,
     swap tables. The existing
     `library_watch_progress_completed_last_watched_at_index` is
     recreated on the new table.

  Not reversible — orphans are gone, columns are gone. PlayableItem
  rows the backfill created remain regardless.

  ## Why both schema and data here

  Paired schema+data migration carve-out from ADR-040: the UPDATEs
  MUST run between the column ADD and the column DROP. The
  `# credo:disable-next-line MC0015` comments document the carve-out.
  """
  use Ecto.Migration
  require Logger

  # UUID v4 synthesised from `randomblob`. Same shape as the Task B
  # migration; defined once to keep the backfill INSERTs consistent.
  @uuid_v4 "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))"

  def up do
    # 1. Add nullable `playable_item_id`.
    alter table(:library_watch_progress) do
      add :playable_item_id,
          references(:library_playable_items, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    # 2. Backfill — pass 1: movies. PlayableItem position = 1
    # (canonical leaf; multi-cut handling is a future task).
    execute("""
    INSERT INTO library_playable_items (id, container_type, container_id, position, inserted_at, updated_at)
    SELECT DISTINCT
      #{@uuid_v4},
      'movie',
      wp.movie_id,
      1,
      datetime('now'),
      datetime('now')
    FROM library_watch_progress wp
    WHERE wp.movie_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'movie'
           AND pi.container_id = wp.movie_id
           AND pi.position = 1
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watch_progress
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              WHERE pi.container_type = 'movie'
                AND pi.container_id = library_watch_progress.movie_id
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
      wp.video_object_id,
      1,
      datetime('now'),
      datetime('now')
    FROM library_watch_progress wp
    WHERE wp.video_object_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'video_object'
           AND pi.container_id = wp.video_object_id
           AND pi.position = 1
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watch_progress
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              WHERE pi.container_type = 'video_object'
                AND pi.container_id = library_watch_progress.video_object_id
                AND pi.position = 1
              LIMIT 1
           )
     WHERE video_object_id IS NOT NULL AND playable_item_id IS NULL
    """)

    # Pass 3: episodes. PlayableItem position = episode_number,
    # matching the Task B convention so multi-part episodes don't
    # collide on `(container_type, container_id)` lookups.
    execute("""
    INSERT INTO library_playable_items (id, container_type, container_id, position, inserted_at, updated_at)
    SELECT DISTINCT
      #{@uuid_v4},
      'episode',
      e.id,
      e.episode_number,
      datetime('now'),
      datetime('now')
    FROM library_watch_progress wp
    JOIN library_episodes e ON e.id = wp.episode_id
    WHERE wp.episode_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_playable_items pi
         WHERE pi.container_type = 'episode'
           AND pi.container_id = e.id
           AND pi.position = e.episode_number
      )
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_watch_progress
       SET playable_item_id = (
             SELECT pi.id FROM library_playable_items pi
              JOIN library_episodes e ON e.id = pi.container_id
             WHERE pi.container_type = 'episode'
               AND e.id = library_watch_progress.episode_id
               AND pi.position = e.episode_number
             LIMIT 1
           )
     WHERE episode_id IS NOT NULL AND playable_item_id IS NULL
    """)

    # 3. Dedupe — keep only the most-recent-by-`last_watched_at` row
    # per `playable_item_id`. The new `UNIQUE(playable_item_id)`
    # constraint would otherwise reject the table rebuild.
    # `rowid` tiebreaks identical timestamps (stable, deterministic
    # in SQLite).
    {:ok, %{rows: [[dupe_count]]}} =
      repo().query("""
      SELECT COUNT(*) - COUNT(DISTINCT playable_item_id)
      FROM library_watch_progress
      WHERE playable_item_id IS NOT NULL
      """)

    if dupe_count > 0 do
      Logger.info(
        "refit_watch_progress_to_playable_item — collapsing #{dupe_count} duplicate WatchProgress rows " <>
          "(keeping the most recent per playable_item_id)"
      )

      # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
      execute("""
      DELETE FROM library_watch_progress
       WHERE playable_item_id IS NOT NULL
         AND rowid NOT IN (
           SELECT rowid FROM (
             SELECT rowid,
                    ROW_NUMBER() OVER (
                      PARTITION BY playable_item_id
                      ORDER BY last_watched_at DESC, rowid DESC
                    ) AS rn
               FROM library_watch_progress
              WHERE playable_item_id IS NOT NULL
           )
          WHERE rn = 1
         )
      """)
    end

    # 4. Delete remaining orphan rows — leaf entity is gone.
    {:ok, %{rows: [[orphan_count]]}} =
      repo().query("SELECT COUNT(*) FROM library_watch_progress WHERE playable_item_id IS NULL")

    if orphan_count > 0 do
      Logger.info(
        "refit_watch_progress_to_playable_item — deleting #{orphan_count} dangling WatchProgress rows " <>
          "(no PlayableItem could be resolved)"
      )

      # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
      execute("DELETE FROM library_watch_progress WHERE playable_item_id IS NULL")
    end

    # 5. Drop legacy FK columns, promote `playable_item_id` to NOT
    # NULL, add UNIQUE(playable_item_id). SQLite table-rebuild dance.
    execute("PRAGMA foreign_keys = OFF")

    # The existing covering index on `(completed, last_watched_at)`
    # is dropped along with the old table — recreated below on the
    # new table.
    drop_if_exists index(:library_watch_progress, [:completed, :last_watched_at],
                     name: :library_watch_progress_completed_last_watched_at_index
                   )

    create table(:library_watch_progress_new, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position_seconds, :float, default: 0.0
      add :duration_seconds, :float, default: 0.0
      add :completed, :boolean, default: false
      add :last_watched_at, :utc_datetime

      add :playable_item_id,
          references(:library_playable_items, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps()
    end

    execute("""
    INSERT INTO library_watch_progress_new
      (id, position_seconds, duration_seconds, completed, last_watched_at,
       playable_item_id, inserted_at, updated_at)
    SELECT id, position_seconds, duration_seconds, completed, last_watched_at,
           playable_item_id, inserted_at, updated_at
    FROM library_watch_progress
    """)

    drop table(:library_watch_progress)

    rename table(:library_watch_progress_new), to: table(:library_watch_progress)

    create unique_index(:library_watch_progress, [:playable_item_id])

    create index(:library_watch_progress, [:completed, :last_watched_at],
             name: :library_watch_progress_completed_last_watched_at_index
           )

    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    raise Ecto.MigrationError,
          "refit_watch_progress_to_playable_item is not reversible — the three legacy FK columns " <>
            "were dropped and orphan WatchProgress rows were deleted destructively."
  end
end
