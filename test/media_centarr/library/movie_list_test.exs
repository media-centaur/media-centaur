defmodule MediaCentarr.Library.MovieListTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Library.MovieList

  import MediaCentarr.TestFactory

  describe "list_available/1" do
    test "returns sorted {ordinal, movie_id, content_url} tuples for movies with content_url" do
      movie_a = build_movie(%{name: "Part 1", content_url: "/m1.mkv", position: 0})
      movie_b = build_movie(%{name: "Part 2", content_url: "/m2.mkv", position: 1})
      entity = build_entity(%{type: :movie_series, movies: [movie_b, movie_a]})

      assert MovieList.list_available(entity) == [
               {1, movie_a.id, "/m1.mkv"},
               {2, movie_b.id, "/m2.mkv"}
             ]
    end

    test "skips movies without content_url" do
      movie_a = build_movie(%{name: "Part 1", content_url: "/m1.mkv", position: 0})
      movie_b = build_movie(%{name: "Part 2", content_url: nil, position: 1})
      entity = build_entity(%{type: :movie_series, movies: [movie_a, movie_b]})

      assert MovieList.list_available(entity) == [{1, movie_a.id, "/m1.mkv"}]
    end

    test "handles empty movies list" do
      entity = build_entity(%{type: :movie_series, movies: []})
      assert MovieList.list_available(entity) == []
    end

    test "sorts chronologically by date_published, then position as tiebreaker" do
      movie_a =
        build_movie(%{name: "A", content_url: "/a.mkv", position: 2, date_published: "2018"})

      movie_b =
        build_movie(%{name: "B", content_url: "/b.mkv", position: 1, date_published: "2020"})

      movie_c =
        build_movie(%{name: "C", content_url: "/c.mkv", position: 3, date_published: "2018"})

      entity = build_entity(%{type: :movie_series, movies: [movie_a, movie_b, movie_c]})

      result = MovieList.list_available(entity)
      # Same date (2018): A (pos 2) before C (pos 3); then B (2020) last
      assert [{1, _, "/a.mkv"}, {2, _, "/c.mkv"}, {3, _, "/b.mkv"}] = result
    end
  end

  describe "index_progress_by_movie/1 (via EpisodeList.index_progress_by_key/1)" do
    test "indexes progress records by movie_id FK" do
      movie_id_a = Ecto.UUID.generate()
      movie_id_b = Ecto.UUID.generate()

      progress_a = build_progress(%{movie_id: movie_id_a, position_seconds: 30.0})
      progress_b = build_progress(%{movie_id: movie_id_b, position_seconds: 60.0})

      alias MediaCentarr.Library.EpisodeList
      index = EpisodeList.index_progress_by_key([progress_a, progress_b])

      assert index[movie_id_a] == progress_a
      assert index[movie_id_b] == progress_b
      assert map_size(index) == 2
    end
  end

  describe "index_progress_by_movie/1" do
    test "indexes by movie_id from movies with preloaded watch_progress" do
      progress_a = build_progress(%{position_seconds: 30.0})
      progress_b = build_progress(%{position_seconds: 60.0})

      movie_a = build_movie(%{name: "Part 1", watch_progress: progress_a})
      movie_b = build_movie(%{name: "Part 2", watch_progress: progress_b})

      index = MovieList.index_progress_by_movie([movie_a, movie_b])

      assert index[movie_a.id] == progress_a
      assert index[movie_b.id] == progress_b
      assert map_size(index) == 2
    end

    test "skips movies without watch_progress" do
      progress = build_progress(%{position_seconds: 30.0})
      movie_a = build_movie(%{name: "Part 1", watch_progress: progress})
      movie_b = build_movie(%{name: "Part 2", watch_progress: nil})

      index = MovieList.index_progress_by_movie([movie_a, movie_b])

      assert index[movie_a.id] == progress
      assert map_size(index) == 1
    end

    test "returns empty map for empty list" do
      assert MovieList.index_progress_by_movie([]) == %{}
    end

    test "returns empty map for non-list" do
      assert MovieList.index_progress_by_movie(nil) == %{}
    end
  end

  describe "find_by_content_url/2" do
    test "returns {ordinal, movie_id, movie_name} for matching url" do
      movie_a = build_movie(%{name: "First", content_url: "/m1.mkv", position: 0})
      movie_b = build_movie(%{name: "Second", content_url: "/m2.mkv", position: 1})
      entity = build_entity(%{type: :movie_series, movies: [movie_a, movie_b]})

      assert {1, movie_a.id, "First"} == MovieList.find_by_content_url(entity, "/m1.mkv")
      assert {2, movie_b.id, "Second"} == MovieList.find_by_content_url(entity, "/m2.mkv")
    end

    test "returns nil when no match" do
      movie = build_movie(%{name: "Only", content_url: "/m1.mkv", position: 0})
      entity = build_entity(%{type: :movie_series, movies: [movie]})

      assert MovieList.find_by_content_url(entity, "/nonexistent.mkv") == nil
    end
  end

  describe "find_movie_by_ordinal/2" do
    test "returns {movie_id, movie_name} for valid ordinal" do
      movie_a = build_movie(%{name: "First", content_url: "/m1.mkv", position: 0})
      movie_b = build_movie(%{name: "Second", content_url: "/m2.mkv", position: 1})
      entity = build_entity(%{type: :movie_series, movies: [movie_a, movie_b]})

      assert {movie_a.id, "First"} == MovieList.find_movie_by_ordinal(entity, 1)
      assert {movie_b.id, "Second"} == MovieList.find_movie_by_ordinal(entity, 2)
    end

    test "returns nil for out-of-range ordinal" do
      movie = build_movie(%{name: "Only", content_url: "/m1.mkv", position: 0})
      entity = build_entity(%{type: :movie_series, movies: [movie]})

      assert MovieList.find_movie_by_ordinal(entity, 99) == nil
    end
  end

  describe "total_available/1" do
    test "counts movies with content_url" do
      movie_a = build_movie(%{content_url: "/m1.mkv", position: 0})
      movie_b = build_movie(%{content_url: nil, position: 1})
      movie_c = build_movie(%{content_url: "/m3.mkv", position: 2})
      entity = build_entity(%{type: :movie_series, movies: [movie_a, movie_b, movie_c]})

      assert MovieList.total_available(entity) == 2
    end
  end
end
