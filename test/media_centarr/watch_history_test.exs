defmodule MediaCentarr.WatchHistoryTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.TestFactory
  alias MediaCentarr.WatchHistory

  describe "rewatch_count/2" do
    test "returns count for an entity with events" do
      movie = TestFactory.create_movie(%{name: "Sample Movie"})
      for _ <- 1..3, do: TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})

      assert WatchHistory.rewatch_count(:movie, movie.id) == 3
    end

    test "returns 0 for an entity with no events" do
      movie = TestFactory.create_movie(%{name: "Dark City"})
      assert WatchHistory.rewatch_count(:movie, movie.id) == 0
    end
  end

  describe "top_rewatches/1" do
    test "delegates to Rewatch.top_rewatches/1" do
      movie = TestFactory.create_movie(%{name: "Solaris"})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})

      [row] = WatchHistory.top_rewatches(min: 2, limit: 5)

      assert row.entity_id == movie.id
      assert row.count == 2
    end
  end

  describe "rewatch_count_map/1" do
    test "returns a map of entity_id => count for the given type" do
      movie_a = TestFactory.create_movie(%{name: "Stalker"})
      movie_b = TestFactory.create_movie(%{name: "Tarkovsky Collection"})
      TestFactory.create_watch_event(%{movie_id: movie_a.id, entity_type: :movie})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie_b.id, entity_type: :movie})

      counts = WatchHistory.rewatch_count_map(:movie)

      assert counts[movie_a.id] == 1
      assert counts[movie_b.id] == 2
    end
  end
end
