defmodule MediaCentaur.Repo.Migrations.TrackingModeReplacesStatusAndSource do
  @moduledoc """
  Collapses `release_tracking_items.status` and `auto_grab_mode` into one
  `tracking_mode`, and removes `source` ([ADR-065]).

  Four representations of one idea existed. `status` (`watching` /
  `ignored`) was the bell on the library detail panel; `auto_grab_mode`
  (`global` / `off` / `ask` / `all_releases`) was the automation section.
  An `ignored` row was not refreshing its calendar whatever its grab mode
  said, so `status` wins the mapping where the two disagree:

  | was | becomes |
  |---|---|
  | `status = 'ignored'` (any grab mode) | `none` — inert, the durable disarm |
  | `auto_grab_mode = 'off'` | `watch` — the row *was* refreshing its calendar |
  | `auto_grab_mode = 'ask'` | `ask` |
  | `auto_grab_mode = 'all_releases'` | `grab` |
  | `auto_grab_mode = 'global'` (or NULL) | `global` |

  `source` carried one bit of meaning — a `manual` item was a person's
  act — and after this release that act is recorded where it belongs, as
  a watchlist entry. So every `source = 'manual'` item without one gets
  a watchlist entry synthesised from its identity columns, **before**
  `source` is dropped. Without it the invariant fails on first reconcile
  and every manually tracked title is stranded: no library reason, no
  watchlist reason, and the reconcile would delete it.

  The synthesised `title` embed carries only what a tracking item knows
  (`tmdb_id`, `media_type`, `name`); `year`, `release_date`, `poster_path`,
  `backdrop_path` and `overview` are NULL and heal on the next TMDB
  refresh. Artwork is unaffected — it is addressed by `tmdb_id`, not by
  the snapshot.

  [ADR-065]: `decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md`
  """
  use Ecto.Migration

  # UUID v4 synthesised from randomblob — same shape as
  # `RefitWatchProgressToPlayableItem`, because SQLite has no uuid().
  @uuid_v4 "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))"

  @backfill_mode """
  UPDATE release_tracking_items
  SET tracking_mode = CASE
    WHEN status = 'ignored' THEN 'none'
    WHEN auto_grab_mode = 'off' THEN 'watch'
    WHEN auto_grab_mode = 'ask' THEN 'ask'
    WHEN auto_grab_mode = 'all_releases' THEN 'grab'
    ELSE 'global'
  END
  WHERE tracking_mode IS NULL
  """

  @backfill_watchlist """
  INSERT INTO watchlist_items (id, tmdb_id, media_type, title, source, inserted_at, updated_at)
  SELECT
    #{@uuid_v4},
    i.tmdb_id,
    i.media_type,
    json_object(
      'tmdb_id', i.tmdb_id,
      'media_type', i.media_type,
      'name', i.name,
      'year', NULL,
      'release_date', NULL,
      'poster_path', NULL,
      'backdrop_path', NULL,
      'overview', NULL
    ),
    'manual',
    i.inserted_at,
    i.updated_at
  FROM release_tracking_items i
  WHERE i.source = 'manual'
    AND NOT EXISTS (
      SELECT 1 FROM watchlist_items w
      WHERE w.tmdb_id = i.tmdb_id AND w.media_type = i.media_type
    )
  """

  def up do
    alter table(:release_tracking_items) do
      add :tracking_mode, :text
    end

    # The rows must carry their new meaning before the columns holding the
    # old one are dropped; there is no later pass that could reconstruct it.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute(@backfill_mode)
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute(@backfill_watchlist)

    # SQLite refuses to drop a column an index still names.
    drop_if_exists index(:release_tracking_items, [:status])

    alter table(:release_tracking_items) do
      remove :status
      remove :source
      remove :auto_grab_mode
    end

    # The queries that filtered `status = 'watching'` now filter
    # `tracking_mode != 'none'`, and want the index that replaces it.
    create index(:release_tracking_items, [:tracking_mode])
  end

  def down do
    drop_if_exists index(:release_tracking_items, [:tracking_mode])

    alter table(:release_tracking_items) do
      add :status, :text, default: "watching"
      add :source, :text, default: "library"
      add :auto_grab_mode, :text, default: "global"
    end

    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE release_tracking_items
    SET status = CASE WHEN tracking_mode = 'none' THEN 'ignored' ELSE 'watching' END,
        auto_grab_mode = CASE
          WHEN tracking_mode = 'ask' THEN 'ask'
          WHEN tracking_mode = 'grab' THEN 'all_releases'
          WHEN tracking_mode IN ('none', 'watch') THEN 'off'
          ELSE 'global'
        END
    """)

    alter table(:release_tracking_items) do
      remove :tracking_mode
    end

    create index(:release_tracking_items, [:status])
  end
end
