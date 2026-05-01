defmodule MediaCentarr.Library.EntityCascadeTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.EntityCascade

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
  end
end
