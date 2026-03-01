defmodule MediaCentaur.Playback.MovieListTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.MovieList

  import MediaCentaur.TestFactory

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

    test "sorts by position then date_published" do
      movie_a = build_movie(%{name: "A", content_url: "/a.mkv", position: 1})

      movie_b =
        build_movie(%{name: "B", content_url: "/b.mkv", position: 0, date_published: "2020"})

      movie_c =
        build_movie(%{name: "C", content_url: "/c.mkv", position: 0, date_published: "2018"})

      entity = build_entity(%{type: :movie_series, movies: [movie_a, movie_b, movie_c]})

      result = MovieList.list_available(entity)
      assert [{1, _, "/c.mkv"}, {2, _, "/b.mkv"}, {3, _, "/a.mkv"}] = result
    end
  end

  describe "index_progress_by_ordinal/1" do
    test "indexes progress records with season_number=0 by episode_number (ordinal)" do
      progress_a = build_progress(%{season_number: 0, episode_number: 1, position_seconds: 30.0})
      progress_b = build_progress(%{season_number: 0, episode_number: 2, position_seconds: 60.0})

      index = MovieList.index_progress_by_ordinal([progress_a, progress_b])

      assert index[1] == progress_a
      assert index[2] == progress_b
      assert map_size(index) == 2
    end

    test "ignores progress records with non-zero season_number" do
      progress = build_progress(%{season_number: 1, episode_number: 1})

      index = MovieList.index_progress_by_ordinal([progress])

      assert index == %{}
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
