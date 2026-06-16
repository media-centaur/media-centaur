defmodule MediaCentaur.Repo.Migrations.AddReleaseIdentityUniqueIndex do
  @moduledoc """
  Enforce one release row per (item, season, episode, part, release_type).

  Release tracking rebuilt an item's releases by delete-then-insert with no
  uniqueness invariant; a rebuild that raced a concurrent rebuild could
  interleave (both delete, both insert) and leave duplicate rows — observed as
  the same episode showing twice on Upcoming. This adds the structural backstop.

  SQLite treats NULLs as distinct in a plain unique index, and episode/part
  columns are NULL for movies (and release_type for TV), so the index COALESCEs
  the nullable keys to sentinels (-1 / '') to make identical rows collide.
  """
  use Ecto.Migration

  @index "release_tracking_releases_identity_index"

  def up do
    # Remove any pre-existing duplicates, keeping the earliest row per identity.
    # Surgical fixup paired with the schema change: the unique index below fails
    # if duplicates remain, so the dedupe must run inline here, not as a separate
    # deferred data migration.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    DELETE FROM release_tracking_releases
    WHERE rowid NOT IN (
      SELECT MIN(rowid)
      FROM release_tracking_releases
      GROUP BY
        item_id,
        COALESCE(season_number, -1),
        COALESCE(episode_number, -1),
        COALESCE(part_tmdb_id, -1),
        COALESCE(release_type, '')
    )
    """)

    execute("""
    CREATE UNIQUE INDEX #{@index}
    ON release_tracking_releases (
      item_id,
      COALESCE(season_number, -1),
      COALESCE(episode_number, -1),
      COALESCE(part_tmdb_id, -1),
      COALESCE(release_type, '')
    )
    """)
  end

  def down do
    execute("DROP INDEX #{@index}")
  end
end
