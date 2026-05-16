defmodule MediaCentarr.Library.TypeResolverTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.TypeResolver

  describe "resolve_container/2 — type dispatch" do
    test "returns {:ok, :tv_series, record} for a TV series UUID" do
      tv_series = create_tv_series(%{name: "Sample Show"})

      assert {:ok, :tv_series, record} = TypeResolver.resolve_container(tv_series.id)
      assert record.id == tv_series.id
      assert record.name == "Sample Show"
    end

    test "returns {:ok, :movie_series, record} for a movie series UUID" do
      series = create_movie_series(%{name: "Sample Trilogy"})

      assert {:ok, :movie_series, record} = TypeResolver.resolve_container(series.id)
      assert record.id == series.id
      assert record.name == "Sample Trilogy"
    end

    test "returns {:ok, :movie, record} for a standalone movie UUID" do
      movie = create_standalone_movie(%{name: "Standalone Movie"})

      assert {:ok, :movie, record} = TypeResolver.resolve_container(movie.id)
      assert record.id == movie.id
      assert record.movie_series_id == nil
    end

    test "returns {:ok, :video_object, record} for a video object UUID" do
      video = create_video_object(%{name: "Sample Video"})

      assert {:ok, :video_object, record} = TypeResolver.resolve_container(video.id)
      assert record.id == video.id
      assert record.name == "Sample Video"
    end

    test "returns :not_found for a UUID that doesn't exist in any type table" do
      assert TypeResolver.resolve_container(Ecto.UUID.generate()) == :not_found
    end
  end

  describe "resolve_container/2 — :standalone_movie option" do
    test "default (true): a series-child movie is NOT matched" do
      series = create_movie_series(%{name: "Series"})
      child = create_movie(%{name: "Child", movie_series_id: series.id, position: 0})

      # Child movie has movie_series_id set, so the default standalone_movie: true
      # filter rejects it. The lookup falls through to video_object (also nothing)
      # and returns :not_found.
      assert TypeResolver.resolve_container(child.id) == :not_found
    end

    test "standalone_movie: false matches a series-child movie" do
      series = create_movie_series(%{name: "Series"})
      child = create_movie(%{name: "Child", movie_series_id: series.id, position: 0})

      assert {:ok, :movie, record} =
               TypeResolver.resolve_container(child.id, standalone_movie: false)

      assert record.id == child.id
      assert record.movie_series_id == series.id
    end
  end

  describe "resolve_container/2 — :preload option" do
    test "preloads associations on the resolved tv_series" do
      tv_series = create_tv_series(%{name: "Preloaded Show"})

      create_image(%{
        tv_series_id: tv_series.id,
        role: "poster",
        content_url: "#{tv_series.id}/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, :tv_series, record} =
               TypeResolver.resolve_container(tv_series.id, preload: [tv_series: [:images]])

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

      assert {:ok, :movie, record} =
               TypeResolver.resolve_container(movie.id, preload: [movie: [:images]])

      assert is_list(record.images)
      assert length(record.images) == 1
    end

    test "no preload option returns record without preloaded associations" do
      tv_series = create_tv_series(%{name: "No Preload"})

      assert {:ok, :tv_series, record} = TypeResolver.resolve_container(tv_series.id)
      # images is the unloaded association struct, not a list
      refute is_list(record.images)
    end
  end

  describe "resolve_by_playable_item/2 — dispatch via PlayableItem" do
    test "returns {:ok, :movie, item, container} for a movie PlayableItem" do
      movie = create_standalone_movie(%{name: "PI Movie"})

      {:ok, item} =
        MediaCentarr.Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 1
        })

      assert {:ok, :movie, returned_item, container} =
               TypeResolver.resolve_by_playable_item(item.id)

      assert returned_item.id == item.id
      assert container.id == movie.id
      assert container.name == "PI Movie"
    end

    test "returns {:ok, :episode, item, container} for an episode PlayableItem" do
      tv_series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1, name: "E1"})

      {:ok, item} =
        MediaCentarr.Library.create_playable_item(%{
          container_type: :episode,
          container_id: episode.id,
          position: 1
        })

      assert {:ok, :episode, returned_item, container} =
               TypeResolver.resolve_by_playable_item(item.id)

      assert returned_item.id == item.id
      assert container.id == episode.id
    end

    test "returns {:ok, :video_object, item, container} for a video_object PlayableItem" do
      video = create_video_object(%{name: "Sample Video"})

      {:ok, item} =
        MediaCentarr.Library.create_playable_item(%{
          container_type: :video_object,
          container_id: video.id,
          position: 1
        })

      assert {:ok, :video_object, returned_item, container} =
               TypeResolver.resolve_by_playable_item(item.id)

      assert returned_item.id == item.id
      assert container.id == video.id
    end

    test "returns :not_found for a non-existent PlayableItem UUID" do
      assert TypeResolver.resolve_by_playable_item(Ecto.UUID.generate()) == :not_found
    end

    test "returns :not_found when PlayableItem exists but container is missing" do
      # Orphan PlayableItem — the `container_id` link has no DB-level FK
      # enforcement (PlayableItem moduledoc — discriminator design).
      movie = create_standalone_movie(%{name: "About to delete"})

      {:ok, item} =
        MediaCentarr.Library.create_playable_item(%{
          container_type: :movie,
          container_id: movie.id,
          position: 1
        })

      # Force-delete the container without going through the cascade so we
      # can simulate an orphan.
      MediaCentarr.Repo.delete!(movie)

      assert TypeResolver.resolve_by_playable_item(item.id) == :not_found
    end
  end
end
