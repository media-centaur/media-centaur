defmodule MediaCentarr.TestFactory do
  @moduledoc """
  Shared test data builders.

  - `build_*` functions return structs or maps with sensible defaults (no DB).
    Use for pure-function tests (Serializer, Mapper, ProgressSummary, etc.).
    Note: `build_entity` returns a plain map (normalized entity shape);
    `build_tv_series`, `build_movie_series`, etc. return Ecto structs.
  - `create_*` functions persist via context functions and return loaded records.
    Use for resource tests and channel tests.
  """

  alias MediaCentarr.Library

  alias MediaCentarr.Library.{
    Extra,
    Image,
    ExternalId,
    Movie,
    MovieSeries,
    Season,
    Episode,
    TVSeries,
    VideoObject
  }

  alias MediaCentarr.Review

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
      external_ids: [],
      movies: [],
      extras: [],
      seasons: [],
      watched_files: [],
      watch_progress: [],
      extra_progress: []
    }

    Map.merge(defaults, overrides)
  end

  def build_image(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      role: "poster",
      content_url: nil,
      extension: "jpg",
      movie_id: nil,
      episode_id: nil
    }

    struct(Image, Map.merge(defaults, overrides))
  end

  def build_external_id(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      source: "tmdb",
      external_id: "12345"
    }

    struct(ExternalId, Map.merge(defaults, overrides))
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
      status: nil,
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
      episode_id: nil,
      movie_id: nil,
      video_object_id: nil,
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
      status: nil,
      seasons: [],
      images: [],
      extras: [],
      external_ids: [],
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
      external_ids: [],
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
      external_ids: [],
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
      status: nil,
      movie_series_id: nil,
      images: [],
      extras: [],
      external_ids: [],
      watched_files: [],
      watch_progress: nil
    }

    struct(Movie, Map.merge(defaults, overrides))
  end

  # ---------------------------------------------------------------------------
  # create_* — persisted via context functions, returns loaded records
  # ---------------------------------------------------------------------------

  def create_entity(attrs \\ %{}) do
    type = attrs[:type] || :movie
    defaults = %{name: "Test Movie"}
    merged = Map.merge(defaults, Map.delete(attrs, :type))

    case type do
      :movie -> Library.create_movie!(merged)
      :tv_series -> Library.create_tv_series!(merged)
      :movie_series -> Library.create_movie_series!(merged)
      :video_object -> Library.create_video_object!(merged)
    end
  end

  def create_image(attrs) do
    Library.create_image!(attrs)
  end

  def create_external_id(attrs) do
    Library.create_external_id!(attrs)
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
    type = attrs[:type] || :movie
    record = create_entity(attrs)
    fk = type_fk(type)

    create_image(%{
      fk => record.id,
      role: "poster",
      content_url: "#{record.id}/poster.jpg",
      extension: "jpg"
    })

    create_external_id(%{
      fk => record.id,
      source: "tmdb",
      external_id: attrs[:tmdb_id] || "99999"
    })

    # Reload with associations
    case type do
      :movie -> Library.get_movie_with_associations!(record.id)
      :tv_series -> Library.get_tv_series_with_associations!(record.id)
      :movie_series -> Library.get_movie_series_with_associations!(record.id)
      :video_object -> Library.get_video_object_with_associations!(record.id)
    end
  end

  defp type_fk(:movie), do: :movie_id
  defp type_fk(:tv_series), do: :tv_series_id
  defp type_fk(:movie_series), do: :movie_series_id
  defp type_fk(:video_object), do: :video_object_id

  def create_linked_file(attrs \\ %{}) do
    defaults = %{
      file_path: "/media/test/#{Ecto.UUID.generate()}.mkv",
      watch_dir: "/media/test"
    }

    Library.link_file!(Map.merge(defaults, attrs))
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
    merged = Map.merge(defaults, attrs)

    cond do
      merged[:movie_id] -> Library.find_or_create_watch_progress_for_movie(merged)
      merged[:episode_id] -> Library.find_or_create_watch_progress_for_episode(merged)
      merged[:video_object_id] -> Library.find_or_create_watch_progress_for_video_object(merged)
    end
    |> then(fn {:ok, record} -> record end)
  end

  def create_extra_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}
    Library.find_or_create_extra_progress!(Map.merge(defaults, attrs))
  end

  # ---------------------------------------------------------------------------
  # Release Tracking
  # ---------------------------------------------------------------------------

  alias MediaCentarr.ReleaseTracking

  def build_tracking_item(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      tmdb_id: :rand.uniform(999_999),
      media_type: :tv_series,
      name: "Test Tracked Series",
      status: :watching,
      source: :library,
      library_entity_id: nil,
      last_refreshed_at: nil,
      poster_path: nil,
      last_library_season: 0,
      last_library_episode: 0,
      releases: [],
      events: []
    }

    struct(ReleaseTracking.Item, Map.merge(defaults, overrides))
  end

  def build_tracking_release(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      air_date: Date.add(Date.utc_today(), 30),
      title: "Episode 1",
      season_number: 1,
      episode_number: 1,
      released: false,
      item_id: nil
    }

    struct(ReleaseTracking.Release, Map.merge(defaults, overrides))
  end

  def build_tracking_event(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      event_type: :began_tracking,
      description: "Began tracking Test Series",
      item_name: "Test Series",
      metadata: %{},
      item_id: nil
    }

    struct(ReleaseTracking.Event, Map.merge(defaults, overrides))
  end

  def create_tracking_item(attrs \\ %{}) do
    defaults = %{
      tmdb_id: :rand.uniform(999_999),
      media_type: :tv_series,
      name: "Test Tracked Series"
    }

    ReleaseTracking.track_item!(Map.merge(defaults, attrs))
  end

  def create_tracking_release(attrs) do
    ReleaseTracking.create_release!(attrs)
  end

  # ---------------------------------------------------------------------------
  # WatchHistory
  # ---------------------------------------------------------------------------

  def build_watch_event(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      entity_type: :movie,
      movie_id: nil,
      episode_id: nil,
      video_object_id: nil,
      title: "Test Movie",
      duration_seconds: 7200.0,
      completed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    struct(MediaCentarr.WatchHistory.Event, Map.merge(defaults, overrides))
  end

  def create_watch_event(attrs \\ %{}) do
    defaults = %{
      entity_type: :movie,
      title: "Test Movie",
      duration_seconds: 7200.0,
      completed_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    {:ok, event} =
      Map.merge(defaults, attrs)
      |> MediaCentarr.WatchHistory.create_event()

    event
  end
end
