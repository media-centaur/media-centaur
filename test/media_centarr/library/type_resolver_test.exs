defmodule MediaCentarr.Library.TypeResolverTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.TypeResolver

  describe "resolve/2 — type dispatch" do
    test "returns {:ok, :tv_series, record} for a TV series UUID" do
      tv_series = create_tv_series(%{name: "Sample Show"})

      assert {:ok, :tv_series, record} = TypeResolver.resolve(tv_series.id)
      assert record.id == tv_series.id
      assert record.name == "Sample Show"
    end

    test "returns {:ok, :movie_series, record} for a movie series UUID" do
      series = create_movie_series(%{name: "Sample Trilogy"})

      assert {:ok, :movie_series, record} = TypeResolver.resolve(series.id)
      assert record.id == series.id
      assert record.name == "Sample Trilogy"
    end

    test "returns {:ok, :movie, record} for a standalone movie UUID" do
      movie = create_standalone_movie(%{name: "Standalone Movie"})

      assert {:ok, :movie, record} = TypeResolver.resolve(movie.id)
      assert record.id == movie.id
      assert record.movie_series_id == nil
    end

    test "returns {:ok, :video_object, record} for a video object UUID" do
      video = create_video_object(%{name: "Sample Video"})

      assert {:ok, :video_object, record} = TypeResolver.resolve(video.id)
      assert record.id == video.id
      assert record.name == "Sample Video"
    end

    test "returns :not_found for a UUID that doesn't exist in any type table" do
      assert TypeResolver.resolve(Ecto.UUID.generate()) == :not_found
    end
  end

  describe "resolve/2 — :standalone_movie option" do
    test "default (true): a series-child movie is NOT matched" do
      series = create_movie_series(%{name: "Series"})
      child = create_movie(%{name: "Child", movie_series_id: series.id, position: 0})

      # Child movie has movie_series_id set, so the default standalone_movie: true
      # filter rejects it. The lookup falls through to video_object (also nothing)
      # and returns :not_found.
      assert TypeResolver.resolve(child.id) == :not_found
    end

    test "standalone_movie: false matches a series-child movie" do
      series = create_movie_series(%{name: "Series"})
      child = create_movie(%{name: "Child", movie_series_id: series.id, position: 0})

      assert {:ok, :movie, record} = TypeResolver.resolve(child.id, standalone_movie: false)
      assert record.id == child.id
      assert record.movie_series_id == series.id
    end
  end

  describe "resolve/2 — :preload option" do
    test "preloads associations on the resolved tv_series" do
      tv_series = create_tv_series(%{name: "Preloaded Show"})

      create_image(%{
        tv_series_id: tv_series.id,
        role: "poster",
        content_url: "#{tv_series.id}/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, :tv_series, record} =
               TypeResolver.resolve(tv_series.id, preload: [tv_series: [:images]])

      assert is_list(record.images)
      assert length(record.images) == 1
      assert hd(record.images).role == "poster"
    end

    test "preloads associations on the resolved standalone movie" do
      movie = create_standalone_movie(%{name: "Preloaded Movie"})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, :movie, record} = TypeResolver.resolve(movie.id, preload: [movie: [:images]])

      assert is_list(record.images)
      assert length(record.images) == 1
    end

    test "no preload option returns record without preloaded associations" do
      tv_series = create_tv_series(%{name: "No Preload"})

      assert {:ok, :tv_series, record} = TypeResolver.resolve(tv_series.id)
      # images is the unloaded association struct, not a list
      refute is_list(record.images)
    end
  end
end
