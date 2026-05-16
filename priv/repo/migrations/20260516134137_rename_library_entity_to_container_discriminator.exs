defmodule MediaCentarr.Repo.Migrations.RenameLibraryEntityToContainerDiscriminator do
  @moduledoc """
  Library Schema v2 — Phase 2 Task J.

  Renames `release_tracking_items.library_entity_id` to the
  Phase 2 discriminator pair `(library_container_type,
  library_container_id)`. The legacy column was a "type-implicit"
  pointer at a Library container (TVSeries for `:tv_series` items,
  MovieSeries for `:movie` items). After this migration the link is
  spelled out the same way Image / Extra / ExternalId spell theirs.

  Type derivation at backfill time:

    * `media_type = :tv_series`  → `library_container_type = :tv_series`
    * `media_type = :movie`      → `library_container_type = :movie_series`

  The `:movie` case picks `:movie_series` because every existing
  `:movie` tracking item was created by the Scanner from a TMDB
  collection (`scanner.ex#process_collection/2`) and points at a
  MovieSeries id. Solo-movie tracking via search uses the fallback
  path in `release_tracking.ex#do_track_from_search/3` which leaves
  the container unset — those rows stay NULL on both columns and
  are unaffected by the backfill.

  `media_type` survives this migration: it still answers a different
  question ("which TMDB resource?") consumed by `tmdb_type_for/1`
  and by Acquisition's `Pursuit.tmdb_type`. Container_type answers
  "which Library schema owns the linked container?". They happen to
  be 1:1 today but they don't have to stay that way (a solo Movie
  link would be `media_type: :movie, container_type: :movie`).

  Not reversible — the legacy column is dropped destructively.
  """
  use Ecto.Migration

  def up do
    execute("PRAGMA foreign_keys = OFF")

    alter table(:release_tracking_items) do
      add :library_container_type, :string
      add :library_container_id, :binary_id
    end

    flush()

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE release_tracking_items
    SET library_container_type = CASE
      WHEN library_entity_id IS NULL THEN NULL
      WHEN media_type = 'tv_series' THEN 'tv_series'
      WHEN media_type = 'movie' THEN 'movie_series'
    END,
    library_container_id = library_entity_id
    """)

    drop_if_exists index(:release_tracking_items, [:library_entity_id])

    # SQLite can't drop a column referenced by an index, and won't
    # drop the legacy column in-place reliably across all versions.
    # Rebuild the table the same way Phase 2 D/E/F did.
    create table(:release_tracking_items_new, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :media_type, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "watching"
      add :source, :string, null: false, default: "library"
      add :library_container_type, :string
      add :library_container_id, :binary_id
      add :last_refreshed_at, :utc_datetime
      add :poster_path, :string
      add :backdrop_path, :string
      add :logo_path, :string
      add :last_library_season, :integer, default: 0
      add :last_library_episode, :integer, default: 0
      add :dismiss_released_before, :date
      add :auto_grab_mode, :string, default: "global"
      add :min_quality, :string
      add :max_quality, :string
      add :quality_4k_patience_hours, :integer
      add :prefer_season_packs, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    execute("""
    INSERT INTO release_tracking_items_new
      (id, tmdb_id, media_type, name, status, source,
       library_container_type, library_container_id,
       last_refreshed_at, poster_path, backdrop_path, logo_path,
       last_library_season, last_library_episode, dismiss_released_before,
       auto_grab_mode, min_quality, max_quality,
       quality_4k_patience_hours, prefer_season_packs,
       inserted_at, updated_at)
    SELECT id, tmdb_id, media_type, name, status, source,
           library_container_type, library_container_id,
           last_refreshed_at, poster_path, backdrop_path, logo_path,
           last_library_season, last_library_episode, dismiss_released_before,
           auto_grab_mode, min_quality, max_quality,
           quality_4k_patience_hours, prefer_season_packs,
           inserted_at, updated_at
    FROM release_tracking_items
    """)

    drop table(:release_tracking_items)
    rename table(:release_tracking_items_new), to: table(:release_tracking_items)

    # Recreate the indexes that lived on the legacy table.
    create unique_index(:release_tracking_items, [:tmdb_id, :media_type],
             name: "release_tracking_items_tmdb_unique"
           )

    create index(:release_tracking_items, [:status])

    create index(:release_tracking_items, [:library_container_type, :library_container_id],
             name: :release_tracking_items_container_index
           )

    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    raise Ecto.MigrationError,
          "rename_library_entity_to_container_discriminator is not reversible — " <>
            "the legacy library_entity_id column was dropped destructively."
  end
end
