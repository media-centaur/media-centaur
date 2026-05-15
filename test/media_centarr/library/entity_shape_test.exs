defmodule MediaCentarr.Library.EntityShapeTest do
  use ExUnit.Case, async: true

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.EntityShape

  describe "normalize/2 — movie" do
    test "carries movie-specific fields through" do
      movie =
        build_standalone_movie(%{
          name: "Sample Movie",
          description: "An overview.",
          duration_seconds: 9000,
          director: "Sample Director",
          content_rating: "PG-13",
          aggregate_rating_value: 8.1,
          content_url: "/media/sample.mkv"
        })

      shape = EntityShape.normalize(movie, :movie)

      assert shape.id == movie.id
      assert shape.type == :movie
      assert shape.name == "Sample Movie"
      assert shape.description == "An overview."
      assert shape.duration_seconds == 9000
      assert shape.director == "Sample Director"
      assert shape.content_rating == "PG-13"
      assert shape.aggregate_rating_value == 8.1
      assert shape.content_url == "/media/sample.mkv"
    end

    test "defaults associations to empty lists" do
      shape = EntityShape.normalize(build_standalone_movie(), :movie)

      assert shape.images == []
      assert shape.external_ids == []
      assert shape.extras == []
      assert shape.seasons == []
      assert shape.movies == []
      assert shape.watched_files == []
      assert shape.watch_progress == []
      assert shape.extra_progress == []
    end

    test "carries cast through to the normalized shape" do
      cast_data = [
        %{
          "name" => "Sample Actor",
          "character" => "Sample Role",
          "tmdb_person_id" => 1,
          "profile_path" => "/p.jpg",
          "order" => 0
        }
      ]

      movie = build_standalone_movie(%{cast: cast_data})

      assert EntityShape.normalize(movie, :movie).cast == cast_data
    end

    test "defaults cast to [] when the record has no cast value" do
      shape = EntityShape.normalize(build_standalone_movie(), :movie)
      assert shape.cast == []
    end

    test "carries crew through to the normalized shape" do
      crew_data = [
        %{
          "tmdb_person_id" => 1,
          "name" => "Sample Director",
          "job" => "Director",
          "department" => "Directing",
          "profile_path" => "/d.jpg"
        }
      ]

      movie = build_standalone_movie(%{crew: crew_data})
      assert EntityShape.normalize(movie, :movie).crew == crew_data
    end

    test "defaults crew to [] when the record has no crew value" do
      shape = EntityShape.normalize(build_standalone_movie(), :movie)
      assert shape.crew == []
    end

    test "derives imdb_id from preloaded :external_ids" do
      imdb_row = build_external_id(%{source: "imdb", external_id: "tt0000001"})
      movie = build_standalone_movie(%{external_ids: [imdb_row]})
      assert EntityShape.normalize(movie, :movie).imdb_id == "tt0000001"
    end
  end

  describe "normalize/2 — tv_series" do
    test "preserves tv_series fields and seasons" do
      season = build_season(%{season_number: 1})
      tv_series = build_tv_series(%{name: "Sample Show", number_of_seasons: 2, seasons: [season]})

      shape = EntityShape.normalize(tv_series, :tv_series)

      assert shape.type == :tv_series
      assert shape.name == "Sample Show"
      assert shape.number_of_seasons == 2
      assert shape.seasons == [season]
    end

    test "duration_seconds is nil for tv_series (field doesn't exist on schema)" do
      shape = EntityShape.normalize(build_tv_series(), :tv_series)
      assert shape.duration_seconds == nil
    end
  end

  describe "normalize/2 — movie_series" do
    test "preserves movie_series fields and child movies" do
      child = build_movie(%{name: "Child Movie"})
      series = build_movie_series(%{name: "Sample Trilogy", movies: [child]})

      shape = EntityShape.normalize(series, :movie_series)

      assert shape.type == :movie_series
      assert shape.name == "Sample Trilogy"
      assert shape.movies == [child]
    end
  end

  describe "normalize/2 — video_object" do
    test "preserves video_object fields" do
      video = build_video_object(%{name: "Sample Video", content_url: "/media/short.mkv"})

      shape = EntityShape.normalize(video, :video_object)

      assert shape.type == :video_object
      assert shape.name == "Sample Video"
      assert shape.content_url == "/media/short.mkv"
    end
  end

  describe "extract_progress/2 — movie" do
    test "wraps single watch_progress in a list" do
      progress = build_progress(%{position_seconds: 120.0})
      movie = build_standalone_movie(%{watch_progress: progress})

      assert EntityShape.extract_progress(movie, :movie) == [progress]
    end

    test "returns empty list when watch_progress is nil" do
      movie = build_standalone_movie(%{watch_progress: nil})
      assert EntityShape.extract_progress(movie, :movie) == []
    end
  end

  describe "extract_progress/2 — video_object" do
    test "wraps single watch_progress in a list" do
      progress = build_progress(%{video_object_id: Ecto.UUID.generate()})
      video = build_video_object(%{watch_progress: progress})

      assert EntityShape.extract_progress(video, :video_object) == [progress]
    end

    test "returns empty list when watch_progress is nil" do
      video = build_video_object(%{watch_progress: nil})
      assert EntityShape.extract_progress(video, :video_object) == []
    end
  end

  describe "extract_progress/2 — tv_series" do
    test "walks seasons → episodes → watch_progress" do
      progress_a = build_progress(%{position_seconds: 100.0})
      progress_b = build_progress(%{position_seconds: 200.0})

      ep_with_a = Map.put(build_episode(%{episode_number: 1}), :watch_progress, progress_a)
      ep_with_b = Map.put(build_episode(%{episode_number: 2}), :watch_progress, progress_b)
      ep_without = Map.put(build_episode(%{episode_number: 3}), :watch_progress, nil)

      season = build_season(%{episodes: [ep_with_a, ep_with_b, ep_without]})
      tv_series = build_tv_series(%{seasons: [season]})

      assert EntityShape.extract_progress(tv_series, :tv_series) == [progress_a, progress_b]
    end

    test "returns empty list for series with no seasons" do
      tv_series = build_tv_series(%{seasons: []})
      assert EntityShape.extract_progress(tv_series, :tv_series) == []
    end
  end

  describe "extract_progress/2 — movie_series" do
    test "walks movies → watch_progress" do
      progress = build_progress(%{position_seconds: 300.0})
      movie_with = Map.put(build_movie(%{name: "M1"}), :watch_progress, progress)
      movie_without = Map.put(build_movie(%{name: "M2"}), :watch_progress, nil)

      series = build_movie_series(%{movies: [movie_with, movie_without]})

      assert EntityShape.extract_progress(series, :movie_series) == [progress]
    end

    test "returns empty list for series with no movies" do
      series = build_movie_series(%{movies: []})
      assert EntityShape.extract_progress(series, :movie_series) == []
    end
  end

  describe "normalize/2 with :collection field" do
    test "movie with preloaded movie_series populates :collection" do
      ms = %MediaCentarr.Library.MovieSeries{
        id: "ms-uuid",
        name: "Mascot Collection"
      }

      record = %MediaCentarr.Library.Movie{
        id: "m-uuid",
        name: "Mascot Cosmos",
        movie_series_id: "ms-uuid",
        movie_series: ms,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      result = EntityShape.normalize(record, :movie)

      assert result.collection == %{id: "ms-uuid", name: "Mascot Collection"}
    end

    test "standalone movie has nil :collection" do
      record = %MediaCentarr.Library.Movie{
        id: "m-uuid",
        name: "Standalone",
        movie_series_id: nil,
        movie_series: nil,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      assert EntityShape.normalize(record, :movie).collection == nil
    end

    test "non-movie types have nil :collection" do
      record = %MediaCentarr.Library.TVSeries{
        id: "tv-uuid",
        name: "Show",
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      assert EntityShape.normalize(record, :tv_series).collection == nil
    end

    test "movie with movie_series_id but unloaded association has nil :collection" do
      record = %MediaCentarr.Library.Movie{
        id: "m-uuid",
        name: "Mascot Cosmos",
        movie_series_id: "ms-uuid",
        movie_series: %Ecto.Association.NotLoaded{},
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }

      assert EntityShape.normalize(record, :movie).collection == nil
    end
  end
end
