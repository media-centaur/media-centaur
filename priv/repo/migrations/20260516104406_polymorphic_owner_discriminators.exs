defmodule MediaCentarr.Repo.Migrations.PolymorphicOwnerDiscriminators do
  @moduledoc """
  Library Schema v2 — Phase 2 Tasks D, E, F (combined).

  Converts three supporting tables from per-type FK polymorphism to
  `(owner_type, owner_id)` discriminator pairs:

    * `library_images`       — owner_type ∈ {movie, episode, tv_series, movie_series, video_object}
    * `library_extras`       — owner_type ∈ {movie, tv_series, movie_series, season}
    * `library_external_ids` — owner_type ∈ {movie, tv_series, movie_series, video_object}

  Per-table unique constraints after this migration:

    * Image:      `unique(owner_type, owner_id, role)` — one image per role per owner.
    * Extra:      none — multiple extras per container is legitimate.
    * ExternalId: `unique(source, external_id, owner_type)` — TMDB Movie #12345
      and TMDB TVSeries #12345 are different namespaces.

  ExternalId's four partial unique indexes (Phase 1 Task 6) collapse to
  one discriminator-aware index.

  ## Sequence

  SQLite doesn't support `ALTER COLUMN` and doesn't support dropping a
  column referenced by an index, so each table follows the standard
  table-rebuild dance:

    1. Add nullable discriminator columns to the original table.
    2. Backfill `(owner_type, owner_id)` from whichever per-type FK is set.
    3. Drop orphan rows that have no FK set (defensive — should not exist
       post-Task-C reseed).
    4. Create the `*_new` table with the target shape (`NOT NULL`
       discriminator columns, new indexes).
    5. Copy rows from the legacy table to the `*_new` table.
    6. Drop the legacy table, rename `*_new` over it, then build indexes.

  Not reversible — old FK columns are dropped destructively.

  ## Why both schema and data here

  Paired schema+data migration carve-out from ADR-040: backfills MUST
  run between the column ADD and the table rebuild. The
  `# credo:disable-next-line MC0015` comments document the carve-out.
  """
  use Ecto.Migration

  def up do
    execute("PRAGMA foreign_keys = OFF")

    refit_library_images()
    refit_library_extras()
    refit_library_external_ids()

    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    raise Ecto.MigrationError,
          "polymorphic_owner_discriminators is not reversible — " <>
            "the per-type FK columns were dropped destructively."
  end

  # ---------------------------------------------------------------------------
  # library_images
  # ---------------------------------------------------------------------------

  defp refit_library_images do
    alter table(:library_images) do
      add :owner_type, :string
      add :owner_id, :binary_id
    end

    flush()

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_images
    SET owner_type = CASE
      WHEN movie_id IS NOT NULL THEN 'movie'
      WHEN episode_id IS NOT NULL THEN 'episode'
      WHEN tv_series_id IS NOT NULL THEN 'tv_series'
      WHEN movie_series_id IS NOT NULL THEN 'movie_series'
      WHEN video_object_id IS NOT NULL THEN 'video_object'
    END,
    owner_id = COALESCE(movie_id, episode_id, tv_series_id, movie_series_id, video_object_id)
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("DELETE FROM library_images WHERE owner_type IS NULL")

    # Drop legacy per-FK-and-role unique indexes before the rebuild —
    # they reference columns about to disappear.
    drop_if_exists index(:library_images, [:movie_id, :role],
                     name: :images_unique_movie_role_index
                   )

    drop_if_exists index(:library_images, [:episode_id, :role],
                     name: :images_unique_episode_role_index
                   )

    drop_if_exists index(:library_images, [:tv_series_id, :role],
                     name: :library_images_unique_tv_series_role_index
                   )

    drop_if_exists index(:library_images, [:movie_series_id, :role],
                     name: :library_images_unique_movie_series_role_index
                   )

    drop_if_exists index(:library_images, [:video_object_id, :role],
                     name: :library_images_unique_video_object_role_index
                   )

    create table(:library_images_new, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string
      add :content_url, :string
      add :extension, :string
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false

      timestamps()
    end

    execute("""
    INSERT INTO library_images_new
      (id, role, content_url, extension, owner_type, owner_id, inserted_at, updated_at)
    SELECT id, role, content_url, extension, owner_type, owner_id, inserted_at, updated_at
    FROM library_images
    """)

    drop table(:library_images)
    rename table(:library_images_new), to: table(:library_images)

    create unique_index(:library_images, [:owner_type, :owner_id, :role],
             name: :library_images_owner_role_unique
           )
  end

  # ---------------------------------------------------------------------------
  # library_extras
  # ---------------------------------------------------------------------------

  defp refit_library_extras do
    alter table(:library_extras) do
      add :owner_type, :string
      add :owner_id, :binary_id
    end

    flush()

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_extras
    SET owner_type = CASE
      WHEN movie_id IS NOT NULL THEN 'movie'
      WHEN tv_series_id IS NOT NULL THEN 'tv_series'
      WHEN movie_series_id IS NOT NULL THEN 'movie_series'
      WHEN season_id IS NOT NULL THEN 'season'
    END,
    owner_id = COALESCE(movie_id, tv_series_id, movie_series_id, season_id)
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("DELETE FROM library_extras WHERE owner_type IS NULL")

    drop_if_exists index(:library_extras, [:movie_id], name: :library_extras_movie_id_index)

    drop_if_exists index(:library_extras, [:tv_series_id],
                     name: :library_extras_tv_series_id_index
                   )

    drop_if_exists index(:library_extras, [:movie_series_id],
                     name: :library_extras_movie_series_id_index
                   )

    create table(:library_extras_new, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :content_url, :string
      add :position, :integer
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false

      timestamps()
    end

    execute("""
    INSERT INTO library_extras_new
      (id, name, content_url, position, owner_type, owner_id, inserted_at, updated_at)
    SELECT id, name, content_url, position, owner_type, owner_id, inserted_at, updated_at
    FROM library_extras
    """)

    drop table(:library_extras)
    rename table(:library_extras_new), to: table(:library_extras)

    # No unique constraint — multiple extras per container is legitimate.
    create index(:library_extras, [:owner_type, :owner_id], name: :library_extras_owner_index)
  end

  # ---------------------------------------------------------------------------
  # library_external_ids
  # ---------------------------------------------------------------------------

  defp refit_library_external_ids do
    alter table(:library_external_ids) do
      add :owner_type, :string
      add :owner_id, :binary_id
    end

    flush()

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE library_external_ids
    SET owner_type = CASE
      WHEN movie_id IS NOT NULL THEN 'movie'
      WHEN tv_series_id IS NOT NULL THEN 'tv_series'
      WHEN movie_series_id IS NOT NULL THEN 'movie_series'
      WHEN video_object_id IS NOT NULL THEN 'video_object'
    END,
    owner_id = COALESCE(movie_id, tv_series_id, movie_series_id, video_object_id)
    """)

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("DELETE FROM library_external_ids WHERE owner_type IS NULL")

    # Phase 1 Task 6 partial unique indexes collapse to a single
    # discriminator-aware index.
    drop_if_exists index(:library_external_ids, [:source, :external_id],
                     name: :library_external_ids_movie_unique
                   )

    drop_if_exists index(:library_external_ids, [:source, :external_id],
                     name: :library_external_ids_tv_series_unique
                   )

    drop_if_exists index(:library_external_ids, [:source, :external_id],
                     name: :library_external_ids_movie_series_unique
                   )

    drop_if_exists index(:library_external_ids, [:source, :external_id],
                     name: :library_external_ids_video_object_unique
                   )

    drop_if_exists index(:library_external_ids, [:movie_id],
                     name: :library_external_ids_movie_id_index
                   )

    drop_if_exists index(:library_external_ids, [:tv_series_id],
                     name: :library_external_ids_tv_series_id_index
                   )

    drop_if_exists index(:library_external_ids, [:movie_series_id],
                     name: :library_external_ids_movie_series_id_index
                   )

    drop_if_exists index(:library_external_ids, [:video_object_id],
                     name: :library_external_ids_video_object_id_index
                   )

    # The Phase 1 single-column lookup index on (source, external_id) is
    # dropped here and recreated after the table rebuild — it gets
    # carried away with the legacy table.
    drop_if_exists index(:library_external_ids, [:source, :external_id],
                     name: :library_external_ids_source_external_id_lookup
                   )

    create table(:library_external_ids_new, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string
      add :external_id, :string
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false

      timestamps()
    end

    execute("""
    INSERT INTO library_external_ids_new
      (id, source, external_id, owner_type, owner_id, inserted_at, updated_at)
    SELECT id, source, external_id, owner_type, owner_id, inserted_at, updated_at
    FROM library_external_ids
    """)

    drop table(:library_external_ids)
    rename table(:library_external_ids_new), to: table(:library_external_ids)

    # Unique within (source, external_id, owner_type) — a Movie and a
    # TVSeries can both have TMDB id 12345 (different namespaces).
    create unique_index(:library_external_ids, [:source, :external_id, :owner_type],
             name: :library_external_ids_source_external_owner_unique
           )

    # Owner lookup (parent → external_ids preload path).
    create index(:library_external_ids, [:owner_type, :owner_id],
             name: :library_external_ids_owner_index
           )

    # Cross-owner lookup (find any owner by `(source, external_id)`,
    # mirrors the Phase 1 Task 6 lookup index — `ExternalIds.find_owner/2`
    # relies on this for fast scans before joining on owner_type).
    create index(:library_external_ids, [:source, :external_id],
             name: :library_external_ids_source_external_id_lookup
           )
  end
end
