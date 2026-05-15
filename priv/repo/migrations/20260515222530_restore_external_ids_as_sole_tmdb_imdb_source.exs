defmodule MediaCentarr.Repo.Migrations.RestoreExternalIdsAsSoleTmdbImdbSource do
  @moduledoc """
  Library Schema v2 — Phase 1 Task 6.

  Restores `library_external_ids` as the sole source of truth for TMDB
  and IMDB ids on every container schema (Movie, TVSeries, MovieSeries,
  VideoObject). The previous arrangement (introduced under
  `20260504175757_add_tmdb_id_to_entities` and friends) had the
  canonical TMDB id sitting on the container row with redundant — then
  empty — `library_external_ids` rows. That was a half-built
  optimisation; rolling back to a single source removes the duplicate
  write path and lets `ExternalId` carry every off-domain identifier
  uniformly.

  ## Sequence

  1. **Backfill** `library_external_ids` from the container columns
     (`tmdb_id` → `source: "tmdb"` or `"tmdb_collection"` for movie
     series; `imdb_id` → `source: "imdb"` for Movie / TVSeries).
     Idempotent via `INSERT … WHERE NOT EXISTS`.
  2. **Drop** the legacy single-column unique index
     `identifiers_unique_external_id_index` on
     `library_external_ids (source, external_id)`. TMDB IDs can
     legitimately collide across owner types (a movie and a tv series
     can both have TMDB id 12345 — different namespaces). Replace
     with four owner-FK-scoped partial unique indexes so each owner
     enforces uniqueness within its own namespace.
  3. **Drop** the `tmdb_id` / `imdb_id` unique indexes on each
     container.
  4. **Drop** the `tmdb_id` / `imdb_id` columns from each container.
  5. **Index** `(source, external_id)` on `library_external_ids` for
     the new lookup path (`MediaCentarr.Library.ExternalIds.find_owner/2`).

  Not reversible — the columns are dropped destructively. The data
  remains in `library_external_ids` either way.
  """
  use Ecto.Migration

  def up do
    # 1. Backfill external_ids from existing container columns.
    # SQLite has no native UUID function — manually compose a v4-shaped
    # string using `randomblob`. Format: 8-4-4-4-12 hex digits.

    execute("""
    INSERT INTO library_external_ids (id, source, external_id, movie_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
           'tmdb', tmdb_id, id, datetime('now'), datetime('now')
    FROM library_movies
    WHERE tmdb_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.movie_id = library_movies.id
          AND ext.source = 'tmdb'
          AND ext.external_id = library_movies.tmdb_id
      )
    """)

    execute("""
    INSERT INTO library_external_ids (id, source, external_id, movie_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
           'imdb', imdb_id, id, datetime('now'), datetime('now')
    FROM library_movies
    WHERE imdb_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.movie_id = library_movies.id
          AND ext.source = 'imdb'
          AND ext.external_id = library_movies.imdb_id
      )
    """)

    execute("""
    INSERT INTO library_external_ids (id, source, external_id, tv_series_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
           'tmdb', tmdb_id, id, datetime('now'), datetime('now')
    FROM library_tv_series
    WHERE tmdb_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.tv_series_id = library_tv_series.id
          AND ext.source = 'tmdb'
          AND ext.external_id = library_tv_series.tmdb_id
      )
    """)

    execute("""
    INSERT INTO library_external_ids (id, source, external_id, tv_series_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
           'imdb', imdb_id, id, datetime('now'), datetime('now')
    FROM library_tv_series
    WHERE imdb_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.tv_series_id = library_tv_series.id
          AND ext.source = 'imdb'
          AND ext.external_id = library_tv_series.imdb_id
      )
    """)

    execute("""
    INSERT INTO library_external_ids (id, source, external_id, movie_series_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
           'tmdb_collection', tmdb_id, id, datetime('now'), datetime('now')
    FROM library_movie_series
    WHERE tmdb_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.movie_series_id = library_movie_series.id
          AND ext.source = 'tmdb_collection'
          AND ext.external_id = library_movie_series.tmdb_id
      )
    """)

    execute("""
    INSERT INTO library_external_ids (id, source, external_id, video_object_id, inserted_at, updated_at)
    SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
           'tmdb', tmdb_id, id, datetime('now'), datetime('now')
    FROM library_video_objects
    WHERE tmdb_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.video_object_id = library_video_objects.id
          AND ext.source = 'tmdb'
          AND ext.external_id = library_video_objects.tmdb_id
      )
    """)

    # 2. Drop the legacy single-column unique index. TMDB IDs can
    # collide across owner types — uniqueness must scope to the owner.
    drop_if_exists unique_index(:library_external_ids, [:source, :external_id],
                     name: "identifiers_unique_external_id_index"
                   )

    # Owner-FK-scoped partial unique indexes — one per FK type. Each
    # ensures `(source, external_id)` is unique *within* a given owner
    # namespace, but allows the same `(source, external_id)` pair to
    # exist across owner types (a movie and a tv series with the same
    # TMDB id).
    #
    # The unique tuple is `(source, external_id)` only — the FK column
    # appears in the `WHERE` clause, scoping which rows the index covers.
    # Including the FK in the unique tuple would be a no-op: the FK
    # column is row-unique (a UUID), so the composite would never
    # collide.
    create unique_index(:library_external_ids, [:source, :external_id],
             where: "movie_id IS NOT NULL",
             name: :library_external_ids_movie_unique
           )

    create unique_index(:library_external_ids, [:source, :external_id],
             where: "tv_series_id IS NOT NULL",
             name: :library_external_ids_tv_series_unique
           )

    create unique_index(:library_external_ids, [:source, :external_id],
             where: "movie_series_id IS NOT NULL",
             name: :library_external_ids_movie_series_unique
           )

    create unique_index(:library_external_ids, [:source, :external_id],
             where: "video_object_id IS NOT NULL",
             name: :library_external_ids_video_object_unique
           )

    # 3 & 4. Drop tmdb_id / imdb_id columns + their unique indexes.
    drop_if_exists index(:library_movies, [:tmdb_id], name: :library_movies_tmdb_id_index)
    drop_if_exists index(:library_tv_series, [:tmdb_id], name: :library_tv_series_tmdb_id_index)

    drop_if_exists index(:library_movie_series, [:tmdb_id],
                     name: :library_movie_series_tmdb_id_index
                   )

    drop_if_exists index(:library_video_objects, [:tmdb_id],
                     name: :library_video_objects_tmdb_id_index
                   )

    alter table(:library_movies) do
      remove :tmdb_id
      remove :imdb_id
    end

    alter table(:library_tv_series) do
      remove :tmdb_id
      remove :imdb_id
    end

    alter table(:library_movie_series) do
      remove :tmdb_id
    end

    alter table(:library_video_objects) do
      remove :tmdb_id
    end

    # 5. Fast lookup path for `ExternalIds.find_owner/2` — joins on
    # `(source, external_id)` without an owner FK constraint.
    create_if_not_exists index(:library_external_ids, [:source, :external_id],
                           name: :library_external_ids_source_external_id_lookup
                         )
  end

  def down do
    raise Ecto.MigrationError,
          "restore_external_ids_as_sole_tmdb_imdb_source is not reversible — " <>
            "the tmdb_id / imdb_id columns were dropped destructively."
  end
end
