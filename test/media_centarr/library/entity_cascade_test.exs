defmodule MediaCentarr.Library.EntityCascadeTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.EntityCascade
  alias MediaCentarr.Library.PlayableItem

  describe "destroy!/1" do
    test "cascade deletes a TV series with seasons, episodes, images, and external IDs" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "4556"})

      create_image(%{
        tv_series_id: tv_series.id,
        role: "poster",
        content_url: "#{tv_series.id}/poster.jpg",
        extension: "jpg"
      })

      season =
        create_season(%{
          tv_series_id: tv_series.id,
          season_number: 1,
          number_of_episodes: 2
        })

      episode1 =
        create_episode(%{season_id: season.id, episode_number: 1, name: "Episode One"})

      create_image(%{
        episode_id: episode1.id,
        role: "thumb",
        content_url: "#{episode1.id}/thumb.jpg",
        extension: "jpg"
      })

      episode2 = create_episode(%{season_id: season.id, episode_number: 2, name: "Episode Two"})

      create_image(%{
        episode_id: episode2.id,
        role: "thumb",
        content_url: "#{episode2.id}/thumb.jpg",
        extension: "jpg"
      })

      create_extra(%{
        tv_series_id: tv_series.id,
        name: "Gag Reel",
        content_url: "/media/extras/gag.mkv"
      })

      EntityCascade.destroy!(tv_series.id)

      assert {:error, _} = Library.fetch_tv_series(tv_series.id)
      assert Library.list_seasons() == []
      assert Library.list_all_images() == []
    end

    test "cascade deletes a movie with images and external IDs" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/sample.mkv"
        })

      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "78"})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      EntityCascade.destroy!(movie.id)

      assert {:error, _} = Library.fetch_movie(movie.id)
      assert Library.list_all_images() == []
    end

    test "cascade deletes PlayableItem rows for a movie" do
      # Library Schema v2 Phase 2 Task G: every leaf carries a
      # PlayableItem. The cascade must drop it alongside the container
      # because the `container_id` link has no DB-level FK enforcement
      # (PlayableItem moduledoc — discriminator design), so orphan
      # PlayableItems would otherwise survive a destroy!.
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      _item = create_playable_item_for_movie(movie)

      EntityCascade.destroy!(movie.id)

      assert {:error, _} = Library.fetch_movie(movie.id)
      assert Library.list_playable_items_for(:movie, movie.id) == []
    end

    test "cascade deletes PlayableItem rows for a video object" do
      video_object = create_entity(%{type: :video_object, name: "Sample Video"})
      _item = create_playable_item_for_video_object(video_object)

      EntityCascade.destroy!(video_object.id)

      assert {:error, _} = Library.fetch_video_object(video_object.id)
      assert Library.list_playable_items_for(:video_object, video_object.id) == []
    end

    test "cascade deletes PlayableItem rows for every episode of a TV series" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 2})
      episode1 = create_episode(%{season_id: season.id, episode_number: 1, name: "E1"})
      episode2 = create_episode(%{season_id: season.id, episode_number: 2, name: "E2"})

      _item1 = create_playable_item_for_episode(episode1)
      _item2 = create_playable_item_for_episode(episode2)

      EntityCascade.destroy!(tv_series.id)

      assert {:error, _} = Library.fetch_tv_series(tv_series.id)
      assert Library.list_playable_items_for(:episode, episode1.id) == []
      assert Library.list_playable_items_for(:episode, episode2.id) == []
    end

    test "cascade deletes PlayableItem rows for every child movie of a MovieSeries" do
      series = create_entity(%{type: :movie_series, name: "Sample Collection"})

      {:ok, child} =
        Library.create_movie(%{
          name: "Sample Child",
          movie_series_id: series.id,
          content_url: "/media/child.mkv",
          position: 1
        })

      _item = create_playable_item_for_movie(child)

      EntityCascade.destroy!(series.id)

      assert {:error, _} = Library.fetch_movie_series(series.id)
      assert {:error, _} = Library.fetch_movie(child.id)
      assert Library.list_playable_items_for(:movie, child.id) == []
    end

    test "leaves PlayableItems for unrelated containers untouched" do
      target = create_entity(%{type: :movie, name: "Target Movie"})
      untouched = create_entity(%{type: :movie, name: "Untouched Movie"})

      _t_item = create_playable_item_for_movie(target)
      _u_item = create_playable_item_for_movie(untouched)

      EntityCascade.destroy!(target.id)

      assert Library.list_playable_items_for(:movie, target.id) == []
      assert length(Library.list_playable_items_for(:movie, untouched.id)) == 1
      assert MediaCentarr.Repo.aggregate(PlayableItem, :count, :id) == 1
    end
  end
end
