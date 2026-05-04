defmodule MediaCentarr.Repo.Migrations.BackfillEntityTmdbIdFromExternalIds do
  @moduledoc """
  One-shot data migration: copies the canonical TMDB id from
  `library_external_ids` rows into the new `tmdb_id` column on each
  entity table. Operates only on rows where `tmdb_id` is currently
  null, so it's safe to re-run.

  See ADR / commit feat(library): hoist tmdb_id onto every entity.
  External-id rows are intentionally left in place — readers in
  `image_repair`, `release_tracking`, etc. still consult them. A
  separate cleanup migration can drop the redundant rows once those
  readers are switched over.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE library_movies
    SET tmdb_id = (
      SELECT ext.external_id
      FROM library_external_ids ext
      WHERE ext.movie_id = library_movies.id AND ext.source = 'tmdb'
      LIMIT 1
    )
    WHERE tmdb_id IS NULL
      AND EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.movie_id = library_movies.id AND ext.source = 'tmdb'
      )
    """)

    execute("""
    UPDATE library_tv_series
    SET tmdb_id = (
      SELECT ext.external_id
      FROM library_external_ids ext
      WHERE ext.tv_series_id = library_tv_series.id AND ext.source = 'tmdb'
      LIMIT 1
    )
    WHERE tmdb_id IS NULL
      AND EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.tv_series_id = library_tv_series.id AND ext.source = 'tmdb'
      )
    """)

    execute("""
    UPDATE library_movie_series
    SET tmdb_id = (
      SELECT ext.external_id
      FROM library_external_ids ext
      WHERE ext.movie_series_id = library_movie_series.id AND ext.source = 'tmdb_collection'
      LIMIT 1
    )
    WHERE tmdb_id IS NULL
      AND EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.movie_series_id = library_movie_series.id AND ext.source = 'tmdb_collection'
      )
    """)

    execute("""
    UPDATE library_video_objects
    SET tmdb_id = (
      SELECT ext.external_id
      FROM library_external_ids ext
      WHERE ext.video_object_id = library_video_objects.id AND ext.source = 'tmdb'
      LIMIT 1
    )
    WHERE tmdb_id IS NULL
      AND EXISTS (
        SELECT 1 FROM library_external_ids ext
        WHERE ext.video_object_id = library_video_objects.id AND ext.source = 'tmdb'
      )
    """)
  end

  def down, do: :ok
end
