defmodule MediaCentaur.TestFactory do
  @moduledoc """
  Shared test data builders.

  - `build_*` functions return plain structs with sensible defaults (no DB).
    Use for pure-function tests (Serializer, Mapper, ProgressSummary, etc.).
  - `create_*` functions persist via context functions and return loaded records.
    Use for resource tests and channel tests.
  """

  alias MediaCentaur.Library

  alias MediaCentaur.Library.{
    Entity,
    Extra,
    Image,
    Identifier,
    Movie,
    MovieSeries,
    Season,
    Episode,
    TVSeries,
    VideoObject
  }

  alias MediaCentaur.Review

  # ---------------------------------------------------------------------------
  # build_* — plain structs, no database
  # ---------------------------------------------------------------------------

  def build_entity(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      type: :movie,
      name: "Test Movie",
      description: nil,
      date_published: nil,
      genres: nil,
      content_url: nil,
      url: nil,
      duration: nil,
      director: nil,
      content_rating: nil,
      number_of_seasons: nil,
      aggregate_rating_value: nil,
      images: [],
      identifiers: [],
      movies: [],
      extras: [],
      seasons: [],
      watched_files: [],
      watch_progress: [],
      extra_progress: []
    }

    struct(Entity, Map.merge(defaults, overrides))
  end

  def build_image(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      role: "poster",
      content_url: nil,
      extension: "jpg",
      entity_id: nil,
      movie_id: nil,
      episode_id: nil
    }

    struct(Image, Map.merge(defaults, overrides))
  end

  def build_identifier(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      property_id: "tmdb",
      value: "12345",
      entity_id: nil
    }

    struct(Identifier, Map.merge(defaults, overrides))
  end

  def build_movie(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Child Movie",
      description: nil,
      date_published: nil,
      duration: nil,
      director: nil,
      content_rating: nil,
      content_url: nil,
      url: nil,
      aggregate_rating_value: nil,
      tmdb_id: nil,
      position: 0,
      entity_id: nil,
      images: []
    }

    struct(Movie, Map.merge(defaults, overrides))
  end

  def build_extra(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Behind the Scenes",
      content_url: "/path/to/extra.mkv",
      position: 0,
      entity_id: nil,
      season_id: nil
    }

    struct(Extra, Map.merge(defaults, overrides))
  end

  def build_season(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      season_number: 1,
      number_of_episodes: 0,
      name: "Season 1",
      entity_id: nil,
      episodes: [],
      extras: []
    }

    struct(Season, Map.merge(defaults, overrides))
  end

  def build_episode(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      episode_number: 1,
      name: "Pilot",
      description: nil,
      duration: nil,
      content_url: nil,
      season_id: nil,
      images: []
    }

    struct(Episode, Map.merge(defaults, overrides))
  end

  def build_progress(overrides \\ %{}) do
    defaults = %{
      season_number: 0,
      episode_number: 0,
      position_seconds: 0.0,
      duration_seconds: 0.0,
      completed: false,
      last_watched_at: DateTime.utc_now()
    }

    Map.merge(defaults, overrides)
  end

  def build_tv_series(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test TV Series",
      description: nil,
      date_published: nil,
      genres: nil,
      url: nil,
      aggregate_rating_value: nil,
      number_of_seasons: nil,
      seasons: [],
      images: [],
      extras: [],
      identifiers: [],
      watched_files: []
    }

    struct(TVSeries, Map.merge(defaults, overrides))
  end

  def build_movie_series(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Movie Series",
      description: nil,
      date_published: nil,
      genres: nil,
      url: nil,
      aggregate_rating_value: nil,
      movies: [],
      images: [],
      extras: [],
      identifiers: [],
      watched_files: []
    }

    struct(MovieSeries, Map.merge(defaults, overrides))
  end

  def build_video_object(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Video",
      description: nil,
      date_published: nil,
      content_url: nil,
      url: nil,
      images: [],
      identifiers: [],
      watched_files: [],
      watch_progress: nil
    }

    struct(VideoObject, Map.merge(defaults, overrides))
  end

  def build_standalone_movie(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Standalone Movie",
      description: nil,
      date_published: nil,
      duration: nil,
      director: nil,
      content_rating: nil,
      content_url: nil,
      url: nil,
      aggregate_rating_value: nil,
      tmdb_id: nil,
      genres: nil,
      position: 0,
      entity_id: nil,
      movie_series_id: nil,
      images: [],
      extras: [],
      identifiers: [],
      watched_files: [],
      watch_progress: nil
    }

    struct(Movie, Map.merge(defaults, overrides))
  end

  # ---------------------------------------------------------------------------
  # create_* — persisted via context functions, returns loaded records
  # ---------------------------------------------------------------------------

  def create_entity(attrs \\ %{}) do
    defaults = %{type: :movie, name: "Test Movie"}
    Library.create_entity!(Map.merge(defaults, attrs))
  end

  def create_image(attrs) do
    Library.create_image!(attrs)
  end

  def create_identifier(attrs) do
    Library.create_identifier!(attrs)
  end

  def create_season(attrs) do
    Library.create_season!(attrs)
  end

  def create_episode(attrs) do
    Library.create_episode!(attrs)
  end

  def create_movie(attrs) do
    Library.create_movie!(attrs)
  end

  def create_tv_series(attrs \\ %{}) do
    defaults = %{name: "Test TV Series"}
    Library.create_tv_series!(Map.merge(defaults, attrs))
  end

  def create_movie_series(attrs \\ %{}) do
    defaults = %{name: "Test Movie Series"}
    Library.create_movie_series!(Map.merge(defaults, attrs))
  end

  def create_video_object(attrs \\ %{}) do
    defaults = %{name: "Test Video"}
    Library.create_video_object!(Map.merge(defaults, attrs))
  end

  def create_standalone_movie(attrs \\ %{}) do
    defaults = %{name: "Test Standalone Movie", position: 0}
    Library.create_movie!(Map.merge(defaults, attrs))
  end

  def create_extra(attrs) do
    Library.create_extra!(attrs)
  end

  def create_entity_with_associations(attrs \\ %{}) do
    entity = create_entity(attrs)

    create_image(%{
      entity_id: entity.id,
      role: "poster",
      content_url: "#{entity.id}/poster.jpg",
      extension: "jpg"
    })

    create_identifier(%{
      entity_id: entity.id,
      property_id: "tmdb",
      value: attrs[:tmdb_id] || "99999"
    })

    # Reload with associations
    Library.get_entity_with_associations!(entity.id)
  end

  def create_linked_file(attrs \\ %{}) do
    entity = attrs[:entity] || create_entity()

    defaults = %{
      file_path: "/media/test/#{Ecto.UUID.generate()}.mkv",
      watch_dir: "/media/test",
      entity_id: entity.id
    }

    Library.link_file!(Map.merge(defaults, Map.delete(attrs, :entity)))
  end

  def create_pending_file(attrs \\ %{}) do
    defaults = %{
      file_path: "/media/test/#{Ecto.UUID.generate()}.mkv",
      watch_directory: "/media/test",
      parsed_title: "Test File",
      confidence: 0.5,
      tmdb_id: 12345,
      tmdb_type: "movie",
      match_title: "Test Match"
    }

    Review.create_pending_file!(Map.merge(defaults, attrs))
  end

  def create_watch_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}
    Library.find_or_create_watch_progress!(Map.merge(defaults, attrs))
  end

  def create_extra_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}
    Library.find_or_create_extra_progress!(Map.merge(defaults, attrs))
  end
end
