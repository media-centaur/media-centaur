defmodule MediaCentaur.Library.PresentableResolverTest do
  @moduledoc """
  Tests for `Library.Presentable.resolve/1` — the single authority that
  maps any entity id + current possession to a presentable identity
  `{kind, id}`. This is the one rule the browse grid, the detail modal,
  and the now-playing surface all consult, so the movie-vs-collection
  decision can never disagree between surfaces.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library

  # Post library-presence-unification a linked file is a present file.
  defp create_present_file(attrs), do: create_linked_file(attrs)

  describe "resolve_presentable/1 — movies and collections" do
    test "a standalone present movie resolves to itself as a movie" do
      movie = create_standalone_movie(%{name: "Standalone Movie"})
      create_present_file(%{movie_id: movie.id})

      assert Library.Presentable.resolve(movie.id) == {:movie, movie.id}
    end

    test "a collection with a single present movie hoists to that movie (by series id)" do
      ms = create_movie_series(%{name: "Singleton Collection"})
      child = create_movie(%{movie_series_id: ms.id, name: "Only Child", position: 0})
      create_present_file(%{movie_id: child.id})
      # An absent sibling must NOT count toward possession.
      _absent = create_movie(%{movie_series_id: ms.id, name: "Absent Sibling", position: 1})

      assert Library.Presentable.resolve(ms.id) == {:movie, child.id}
    end

    test "a collection with a single present movie hoists to that movie (by movie id)" do
      ms = create_movie_series(%{name: "Singleton Collection"})
      child = create_movie(%{movie_series_id: ms.id, name: "Only Child", position: 0})
      create_present_file(%{movie_id: child.id})

      assert Library.Presentable.resolve(child.id) == {:movie, child.id}
    end

    test "a collection with two present movies resolves to the collection (by series id)" do
      ms = create_movie_series(%{name: "Trilogy"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      create_present_file(%{movie_id: part1.id})
      create_present_file(%{movie_id: part2.id})

      assert Library.Presentable.resolve(ms.id) == {:movie_series, ms.id}
    end

    test "a child of a multi-present collection resolves to the collection (matches the grid)" do
      ms = create_movie_series(%{name: "Trilogy"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      create_present_file(%{movie_id: part1.id})
      create_present_file(%{movie_id: part2.id})

      assert Library.Presentable.resolve(part1.id) == {:movie_series, ms.id}
    end

    test "a collection with no present movies is not presentable" do
      ms = create_movie_series(%{name: "Owned Nothing"})
      _absent = create_movie(%{movie_series_id: ms.id, name: "Absent", position: 0})

      assert Library.Presentable.resolve(ms.id) == :not_found
    end

    test "a movie with no present file is not presentable" do
      movie = create_standalone_movie(%{name: "Orphan Movie"})

      assert Library.Presentable.resolve(movie.id) == :not_found
    end
  end

  describe "resolve_presentable/1 — other kinds" do
    test "a tv series with a present episode resolves to the series" do
      series = create_tv_series(%{name: "Test Show"})
      create_present_file(%{tv_series_id: series.id})

      assert Library.Presentable.resolve(series.id) == {:tv_series, series.id}
    end

    test "a present video object resolves to itself" do
      video = create_video_object(%{name: "Home Video"})
      create_present_file(%{video_object_id: video.id})

      assert Library.Presentable.resolve(video.id) == {:video_object, video.id}
    end

    test "an unknown id is not presentable" do
      assert Library.Presentable.resolve(Ecto.UUID.generate()) == :not_found
    end
  end
end
