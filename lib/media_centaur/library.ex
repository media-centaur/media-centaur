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
  end

  resources do
    resource MediaCentaur.Library.Entity
    resource MediaCentaur.Library.WatchedFile
    resource MediaCentaur.Library.Image
    resource MediaCentaur.Library.Identifier
    resource MediaCentaur.Library.Movie
    resource MediaCentaur.Library.Extra
    resource MediaCentaur.Library.Season
    resource MediaCentaur.Library.Episode
    resource MediaCentaur.Library.WatchProgress
    resource MediaCentaur.Library.Setting
  end
end
