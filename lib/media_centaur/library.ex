defmodule MediaCentaur.Library do
  @moduledoc """
  The media library domain — entities, images, identifiers, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  use Ash.Domain, extensions: [AshAi]

  tools do
    tool :read_entities, MediaCentaur.Library.Entity, :read do
      description "List all entities in the media library"
    end

    tool :read_entity_details, MediaCentaur.Library.Entity, :with_associations do
      description "Read an entity with all associations (images, identifiers, seasons, episodes, movies, extras)"
    end

    tool :read_entity_progress, MediaCentaur.Library.Entity, :with_progress do
      description "Read an entity with watch progress, seasons with episodes, and movies"
    end

    tool :read_watched_files, MediaCentaur.Library.WatchedFile, :read do
      description "List all watched files tracked by the library"
    end

    tool :read_images, MediaCentaur.Library.Image, :read do
      description "List all images in the library"
    end

    tool :read_incomplete_images, MediaCentaur.Library.Image, :incomplete do
      description "List images that have a remote URL but haven't been downloaded yet"
    end

    tool :find_by_tmdb_id, MediaCentaur.Library.Identifier, :find_by_tmdb_id do
      description "Find an entity by its TMDB ID"
    end

    tool :read_watch_progress, MediaCentaur.Library.WatchProgress, :read do
      description "List all watch progress records"
    end

    tool :read_entity_watch_progress, MediaCentaur.Library.WatchProgress, :for_entity do
      description "Read watch progress for a specific entity"
    end

    tool :read_settings, MediaCentaur.Library.Setting, :read do
      description "List all settings"
    end

    # Entity writes
    tool :create_entity, MediaCentaur.Library.Entity, :create_from_tmdb do
      description "Create a new entity from TMDB data (type, name, description, date_published, genres, etc.)"
    end

    tool :set_entity_content_url, MediaCentaur.Library.Entity, :set_content_url do
      description "Set the content URL on an entity"
    end

    tool :destroy_entity, MediaCentaur.Library.Entity, :destroy do
      description "Delete an entity from the library"
    end

    # WatchedFile writes
    tool :link_file, MediaCentaur.Library.WatchedFile, :link_file do
      description "Link a file path to an entity (upserts by file path)"
    end

    tool :destroy_watched_file, MediaCentaur.Library.WatchedFile, :destroy do
      description "Delete a watched file record"
    end

    # Image writes
    tool :create_image, MediaCentaur.Library.Image, :create do
      description "Create an image record (role, url, content_url, extension, entity/movie/episode ID)"
    end

    tool :clear_image_content_url, MediaCentaur.Library.Image, :clear_content_url do
      description "Clear the local content URL of an image (marks it for re-download)"
    end

    tool :destroy_image, MediaCentaur.Library.Image, :destroy do
      description "Delete an image record"
    end

    # Identifier writes
    tool :create_identifier, MediaCentaur.Library.Identifier, :find_or_create do
      description "Create an external identifier for an entity (idempotent upsert)"
    end

    tool :destroy_identifier, MediaCentaur.Library.Identifier, :destroy do
      description "Delete an identifier record"
    end

    # Movie writes
    tool :create_movie, MediaCentaur.Library.Movie, :create do
      description "Create a movie record under an entity"
    end

    tool :destroy_movie, MediaCentaur.Library.Movie, :destroy do
      description "Delete a movie record"
    end

    # Season writes
    tool :create_season, MediaCentaur.Library.Season, :create do
      description "Create a season under an entity"
    end

    tool :destroy_season, MediaCentaur.Library.Season, :destroy do
      description "Delete a season record"
    end

    # Episode writes
    tool :create_episode, MediaCentaur.Library.Episode, :create do
      description "Create an episode under a season"
    end

    tool :destroy_episode, MediaCentaur.Library.Episode, :destroy do
      description "Delete an episode record"
    end

    # WatchProgress writes
    tool :upsert_watch_progress, MediaCentaur.Library.WatchProgress, :upsert_progress do
      description "Create or update watch progress for an entity (position, duration, season/episode)"
    end

    tool :mark_watch_completed, MediaCentaur.Library.WatchProgress, :mark_completed do
      description "Mark a watch progress record as completed"
    end

    # Setting writes
    tool :upsert_setting, MediaCentaur.Library.Setting, :upsert do
      description "Create or update a setting (upserts by key)"
    end

    tool :destroy_setting, MediaCentaur.Library.Setting, :destroy do
      description "Delete a setting"
    end

    # Generic actions (operations, not CRUD)
    tool :parse_filename, MediaCentaur.Library.Entity, :parse_filename do
      description "Parse a video filename into structured metadata (title, year, type, season, episode)"
    end

    tool :resolve_playback, MediaCentaur.Library.Entity, :resolve_playback do
      description "Resolve a UUID into playback parameters (content URL, resume position, episode info)"
    end

    tool :trigger_scan, MediaCentaur.Library.Entity, :trigger_scan do
      description "Trigger a file system scan across all watched directories"
    end

    tool :measure_storage, MediaCentaur.Library.Entity, :measure_storage do
      description "Measure disk usage for watch directories, images, and database"
    end

    tool :watcher_statuses, MediaCentaur.Library.Entity, :watcher_statuses do
      description "Get the current status of all file system watchers"
    end

    tool :serialize_entity, MediaCentaur.Library.Entity, :serialize_entity do
      description "Load and serialize an entity to its schema.org JSON-LD representation"
    end

    tool :clear_database, MediaCentaur.Library.Entity, :clear_database do
      description "Destroy all library records and clear image files from disk (destructive!)"
    end

    tool :refresh_cache, MediaCentaur.Library.Image, :refresh_cache do
      description "Clear all cached artwork from disk and re-download images for all entities"
    end

    tool :retry_incomplete, MediaCentaur.Library.Image, :retry_incomplete do
      description "Re-download images that have a TMDB URL but no local content"
    end

    tool :dismiss_incomplete, MediaCentaur.Library.Image, :dismiss_incomplete do
      description "Delete all image records that have a TMDB URL but no local content"
    end
  end

  resources do
    resource MediaCentaur.Library.Entity do
      define :list_entities, action: :read
      define :get_entity, action: :read, get_by: [:id]
      define :list_entities_with_associations, action: :with_associations
      define :get_entity_with_associations, action: :with_associations, get_by: [:id]
      define :get_entity_with_progress, action: :with_progress, get_by: [:id]
      define :list_entities_with_images, action: :with_images
      define :get_entity_with_images, action: :with_images, get_by: [:id]
      define :list_entities_by_ids, action: :by_ids, args: [:ids]
      define :create_entity, action: :create_from_tmdb
      define :set_entity_content_url, action: :set_content_url
      define :destroy_entity, action: :destroy
    end

    resource MediaCentaur.Library.WatchedFile do
      define :list_watched_files, action: :read
      define :list_watched_files_for_entity, action: :by_entity, args: [:entity_id]
      define :link_file, action: :link_file
      define :mark_file_absent, action: :mark_absent
      define :mark_file_present, action: :mark_present
      define :set_file_absent_since, action: :set_absent_since
      define :list_expired_absent_files, action: :expired_absent, args: [:cutoff]
      define :list_files_by_watch_dir, action: :by_watch_dir, args: [:watch_dir, :state]
      define :list_files_by_paths, action: :by_file_paths, args: [:file_paths]
      define :destroy_watched_file, action: :destroy
    end

    resource MediaCentaur.Library.Image do
      define :list_images, action: :read
      define :list_images_for_entity, action: :by_entity, args: [:entity_id]
      define :list_images_for_episode, action: :by_episode, args: [:episode_id]
      define :list_images_for_movie, action: :by_movie, args: [:movie_id]
      define :list_incomplete_images, action: :incomplete
      define :create_image, action: :create
      define :find_or_create_image, action: :find_or_create
      define :find_or_create_movie_image, action: :find_or_create_for_movie
      define :find_or_create_episode_image, action: :find_or_create_for_episode
      define :update_image, action: :update
      define :clear_image_content_url, action: :clear_content_url
      define :destroy_image, action: :destroy
    end

    resource MediaCentaur.Library.Identifier do
      define :list_identifiers, action: :read
      define :find_or_create_identifier, action: :find_or_create

      define :find_by_tmdb_id,
        action: :find_by_tmdb_id,
        args: [:tmdb_id],
        get?: true,
        not_found_error?: false

      define :find_by_tmdb_collection,
        action: :find_by_tmdb_collection,
        args: [:collection_id],
        get?: true,
        not_found_error?: false

      define :create_identifier, action: :create
      define :destroy_identifier, action: :destroy
    end

    resource MediaCentaur.Library.Movie do
      define :list_movies, action: :read
      define :list_movies_for_entity, action: :by_entity, args: [:entity_id]
      define :get_movie, action: :read, get_by: [:id]
      define :find_or_create_movie, action: :find_or_create
      define :set_movie_content_url, action: :set_content_url
      define :create_movie, action: :create
      define :destroy_movie, action: :destroy
    end

    resource MediaCentaur.Library.Extra do
      define :list_extras, action: :read
      define :list_extras_for_entity, action: :by_entity, args: [:entity_id]
      define :list_extras_for_season, action: :by_season, args: [:season_id]
      define :get_extra, action: :read, get_by: [:id]
      define :find_or_create_extra, action: :find_or_create
      define :create_extra, action: :create
      define :destroy_extra, action: :destroy
    end

    resource MediaCentaur.Library.Season do
      define :list_seasons, action: :read
      define :list_seasons_for_entity, action: :by_entity, args: [:entity_id]
      define :get_season, action: :read, get_by: [:id]
      define :find_or_create_season, action: :find_or_create
      define :create_season, action: :create
      define :destroy_season, action: :destroy
    end

    resource MediaCentaur.Library.Episode do
      define :list_episodes, action: :read
      define :list_episodes_for_season, action: :by_season, args: [:season_id]
      define :get_episode, action: :read, get_by: [:id]
      define :find_or_create_episode, action: :find_or_create
      define :set_episode_content_url, action: :set_content_url
      define :create_episode, action: :create
      define :destroy_episode, action: :destroy
    end

    resource MediaCentaur.Library.WatchProgress do
      define :list_watch_progress, action: :read
      define :list_entity_watch_progress, action: :for_entity, args: [:entity_id]
      define :upsert_watch_progress, action: :upsert_progress
      define :mark_watch_completed, action: :mark_completed
      define :destroy_watch_progress, action: :destroy
    end

    resource MediaCentaur.Library.Setting do
      define :list_settings, action: :read
      define :get_setting_by_key, action: :by_key, args: [:key], get?: true
      define :upsert_setting, action: :upsert
      define :create_setting, action: :create
      define :update_setting, action: :update
      define :destroy_setting, action: :destroy
    end
  end
end
