defmodule MediaCentarr.WatchHistory.RewatchTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.TestFactory
  alias MediaCentarr.WatchHistory.Rewatch

  describe "count_per_entity/1" do
    test "returns 1 for entities watched once" do
      movie = TestFactory.create_movie(%{name: "Once"})
      TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})

      counts = Rewatch.count_per_entity(:movie)

      assert counts[movie.id] == 1
    end

    test "returns N for entities watched N times" do
      movie = TestFactory.create_movie(%{name: "Many Times"})

      for _ <- 1..3 do
        TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})
      end

      counts = Rewatch.count_per_entity(:movie)

      assert counts[movie.id] == 3
    end

    test "scoped to entity_type" do
      movie = TestFactory.create_movie(%{name: "Scoped Movie"})
      tv_series = TestFactory.create_tv_series(%{name: "Test Series"})

      season =
        TestFactory.create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 1})

      episode = TestFactory.create_episode(%{season_id: season.id, name: "Pilot", episode_number: 1})
      TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})
      TestFactory.create_watch_event(%{episode_id: episode.id, entity_type: :episode})

      assert Map.get(Rewatch.count_per_entity(:movie), movie.id) == 1
      assert Map.get(Rewatch.count_per_entity(:episode), episode.id) == 1
      refute Map.has_key?(Rewatch.count_per_entity(:movie), episode.id)
      refute Map.has_key?(Rewatch.count_per_entity(:episode), movie.id)
    end

    test "counts video object events" do
      video = TestFactory.create_video_object(%{name: "Test Video"})

      for _ <- 1..2,
          do: TestFactory.create_watch_event(%{video_object_id: video.id, entity_type: :video_object})

      counts = Rewatch.count_per_entity(:video_object)

      assert counts[video.id] == 2
    end
  end

  describe "top_rewatches/1" do
    test "returns entities sorted by completion count, descending" do
      movie_a = TestFactory.create_movie(%{name: "A"})
      movie_b = TestFactory.create_movie(%{name: "B"})

      TestFactory.create_watch_event(%{movie_id: movie_a.id, entity_type: :movie})

      for _ <- 1..3 do
        TestFactory.create_watch_event(%{movie_id: movie_b.id, entity_type: :movie})
      end

      [first, second | _] = Rewatch.top_rewatches(limit: 10)

      assert first.entity_id == movie_b.id
      assert first.count == 3
      assert second.entity_id == movie_a.id
      assert second.count == 1
    end

    test "filters out entities watched only once when min: 2" do
      movie_a = TestFactory.create_movie(%{name: "Once Only"})
      movie_b = TestFactory.create_movie(%{name: "Twice"})
      TestFactory.create_watch_event(%{movie_id: movie_a.id, entity_type: :movie})

      for _ <- 1..2 do
        TestFactory.create_watch_event(%{movie_id: movie_b.id, entity_type: :movie})
      end

      results = Rewatch.top_rewatches(min: 2)

      assert length(results) == 1
      assert hd(results).entity_id == movie_b.id
    end

    test "filters by entity_type when given" do
      movie = TestFactory.create_movie(%{name: "Movie"})
      tv_series = TestFactory.create_tv_series(%{name: "Test Series"})

      season =
        TestFactory.create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 1})

      episode = TestFactory.create_episode(%{season_id: season.id, name: "Pilot", episode_number: 1})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})
      for _ <- 1..3, do: TestFactory.create_watch_event(%{episode_id: episode.id, entity_type: :episode})

      movie_only = Rewatch.top_rewatches(entity_type: :movie)

      assert length(movie_only) == 1
      assert hd(movie_only).entity_id == movie.id
      assert hd(movie_only).entity_type == :movie
    end

    test "respects :limit and returns the top N by count" do
      movie_a = TestFactory.create_movie(%{name: "A"})
      movie_b = TestFactory.create_movie(%{name: "B"})
      movie_c = TestFactory.create_movie(%{name: "C"})

      TestFactory.create_watch_event(%{movie_id: movie_a.id, entity_type: :movie})
      for _ <- 1..3, do: TestFactory.create_watch_event(%{movie_id: movie_b.id, entity_type: :movie})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie_c.id, entity_type: :movie})

      results = Rewatch.top_rewatches(limit: 2)

      assert length(results) == 2
      ids = Enum.map(results, & &1.entity_id)
      assert ids == [movie_b.id, movie_c.id]
    end
  end
end
