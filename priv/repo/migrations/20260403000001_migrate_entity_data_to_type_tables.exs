defmodule MediaCentarr.Repo.Migrations.MigrateEntityDataToTypeTables do
  @moduledoc """
  Data migration: populate type-specific tables from library_entities and
  re-key all FK references from entity_id to the new type-specific columns.

  Irreversible — the down direction raises.
  """
  use Ecto.Migration

  def up do
    # =========================================================================
    # Step 1: Create type-specific records from Entity rows (preserve UUIDs)
    # =========================================================================

    # --- tv_series ---
    execute("""
    INSERT INTO library_tv_series (id, name, description, date_published, genres, url, aggregate_rating_value, number_of_seasons, inserted_at, updated_at)
    SELECT id, name, description, date_published, genres, url, aggregate_rating_value, number_of_seasons, inserted_at, updated_at
    FROM library_entities
    WHERE type = 'tv_series'
    """)

    # Update seasons to point at the new tv_series record
    execute("""
    UPDATE library_seasons
    SET tv_series_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'tv_series')
    """)

    # --- movie_series ---
    execute("""
    INSERT INTO library_movie_series (id, name, description, date_published, genres, url, aggregate_rating_value, inserted_at, updated_at)
    SELECT id, name, description, date_published, genres, url, aggregate_rating_value, inserted_at, updated_at
    FROM library_entities
    WHERE type = 'movie_series'
    """)

    # Update child movies to point at the new movie_series record
    execute("""
    UPDATE library_movies
    SET movie_series_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
    """)

    # --- standalone movies ---
    # These get a new Movie row with the SAME UUID as the entity.
    execute("""
    INSERT INTO library_movies (id, name, description, date_published, genres, duration, director, content_rating, content_url, url, aggregate_rating_value, entity_id, movie_series_id, tmdb_id, position, inserted_at, updated_at)
    SELECT id, name, description, date_published, genres, duration, director, content_rating, content_url, url, aggregate_rating_value, id, NULL, NULL, NULL, inserted_at, updated_at
    FROM library_entities
    WHERE type = 'movie'
    """)

    # --- video_objects ---
    execute("""
    INSERT INTO library_video_objects (id, name, description, date_published, content_url, url, inserted_at, updated_at)
    SELECT id, name, description, date_published, content_url, url, inserted_at, updated_at
    FROM library_entities
    WHERE type = 'video_object'
    """)

    # =========================================================================
    # Step 2: Re-key FK columns on existing tables
    # =========================================================================

    # --- Images (only those with entity_id set and no movie_id/episode_id) ---

    # movie entities → movie_id
    execute("""
    UPDATE library_images
    SET movie_id = entity_id
    WHERE entity_id IS NOT NULL
      AND movie_id IS NULL
      AND episode_id IS NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'movie')
    """)

    # tv_series entities → tv_series_id
    execute("""
    UPDATE library_images
    SET tv_series_id = entity_id
    WHERE entity_id IS NOT NULL
      AND movie_id IS NULL
      AND episode_id IS NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'tv_series')
    """)

    # movie_series entities → movie_series_id
    execute("""
    UPDATE library_images
    SET movie_series_id = entity_id
    WHERE entity_id IS NOT NULL
      AND movie_id IS NULL
      AND episode_id IS NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
    """)

    # video_object entities → video_object_id
    execute("""
    UPDATE library_images
    SET video_object_id = entity_id
    WHERE entity_id IS NOT NULL
      AND movie_id IS NULL
      AND episode_id IS NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'video_object')
    """)

    # --- Identifiers ---

    execute("""
    UPDATE library_identifiers
    SET movie_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie')
    """)

    execute("""
    UPDATE library_identifiers
    SET tv_series_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'tv_series')
    """)

    execute("""
    UPDATE library_identifiers
    SET movie_series_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
    """)

    execute("""
    UPDATE library_identifiers
    SET video_object_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'video_object')
    """)

    # --- Watched files ---

    execute("""
    UPDATE library_watched_files
    SET movie_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie')
    """)

    execute("""
    UPDATE library_watched_files
    SET tv_series_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'tv_series')
    """)

    execute("""
    UPDATE library_watched_files
    SET movie_series_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
    """)

    execute("""
    UPDATE library_watched_files
    SET video_object_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'video_object')
    """)

    # --- Extras ---
    # Extras with entity_id (no season_id) get re-keyed based on entity type.
    # All 21 extras are entity_only (no season_id), all belong to movie_series entities.

    execute("""
    UPDATE library_extras
    SET movie_id = entity_id
    WHERE entity_id IS NOT NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'movie')
    """)

    execute("""
    UPDATE library_extras
    SET tv_series_id = entity_id
    WHERE entity_id IS NOT NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'tv_series')
    """)

    execute("""
    UPDATE library_extras
    SET movie_series_id = entity_id
    WHERE entity_id IS NOT NULL
      AND entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
    """)

    # --- Watch progress ---

    # Standalone movies: set movie_id directly (entity.id = new movie.id)
    execute("""
    UPDATE library_watch_progress
    SET movie_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie')
    """)

    # Video objects: set video_object_id directly
    execute("""
    UPDATE library_watch_progress
    SET video_object_id = entity_id
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'video_object')
    """)

    # TV series: look up the episode by (season_number, episode_number)
    # through seasons → episodes, set episode_id
    execute("""
    UPDATE library_watch_progress
    SET episode_id = (
      SELECT ep.id
      FROM library_seasons s
      JOIN library_episodes ep ON ep.season_id = s.id
      WHERE s.entity_id = library_watch_progress.entity_id
        AND s.season_number = library_watch_progress.season_number
        AND ep.episode_number = library_watch_progress.episode_number
    )
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'tv_series')
    """)

    # Movie series: look up the movie by ordinal (episode_number = 1-based position).
    # Movies are ordered by (date_published, position). We use ROW_NUMBER to assign
    # the 1-based ordinal, then match on episode_number.
    execute("""
    UPDATE library_watch_progress
    SET movie_id = (
      SELECT ranked.id
      FROM (
        SELECT m.id, m.entity_id,
               ROW_NUMBER() OVER (PARTITION BY m.entity_id ORDER BY m.date_published, m.position) AS ordinal
        FROM library_movies m
        WHERE m.entity_id IS NOT NULL
          AND m.entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
      ) ranked
      WHERE ranked.entity_id = library_watch_progress.entity_id
        AND ranked.ordinal = library_watch_progress.episode_number
    )
    WHERE entity_id IN (SELECT id FROM library_entities WHERE type = 'movie_series')
    """)

    # =========================================================================
    # Step 3: Verify data integrity
    # =========================================================================

    flush()

    verify!(
      "images with entity_id but no type FK",
      """
      SELECT COUNT(*) FROM library_images
      WHERE entity_id IS NOT NULL
        AND movie_id IS NULL AND episode_id IS NULL
        AND tv_series_id IS NULL AND movie_series_id IS NULL
        AND video_object_id IS NULL
      """
    )

    verify!(
      "identifiers with entity_id but no type FK",
      """
      SELECT COUNT(*) FROM library_identifiers
      WHERE entity_id IS NOT NULL
        AND movie_id IS NULL AND tv_series_id IS NULL
        AND movie_series_id IS NULL AND video_object_id IS NULL
      """
    )

    verify!(
      "watched_files with entity_id but no type FK",
      """
      SELECT COUNT(*) FROM library_watched_files
      WHERE entity_id IS NOT NULL
        AND movie_id IS NULL AND tv_series_id IS NULL
        AND movie_series_id IS NULL AND video_object_id IS NULL
      """
    )

    verify!(
      "extras with entity_id but no type FK",
      """
      SELECT COUNT(*) FROM library_extras
      WHERE entity_id IS NOT NULL
        AND movie_id IS NULL AND tv_series_id IS NULL
        AND movie_series_id IS NULL
      """
    )

    verify!(
      "watch_progress without playable-item FK",
      """
      SELECT COUNT(*) FROM library_watch_progress
      WHERE entity_id IS NOT NULL
        AND movie_id IS NULL AND episode_id IS NULL
        AND video_object_id IS NULL
      """
    )
  end

  def down do
    raise "Irreversible migration — cannot undo data migration from entities to type-specific tables"
  end

  defp verify!(label, query) do
    %{rows: [[count]]} = Ecto.Adapters.SQL.query!(MediaCentarr.Repo, query)

    if count > 0 do
      raise "INTEGRITY CHECK FAILED: #{count} #{label}"
    end
  end
end
