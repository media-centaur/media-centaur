defmodule MediaCentaur.Library.EntityCascadeTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library
  alias MediaCentaur.Library.EntityCascade

  describe "destroy!/1" do
    test "cascade deletes a TV series with seasons, episodes, images, and identifiers" do
      tv_series = create_entity(%{type: :tv_series, name: "Sample Show One"})
      create_identifier(%{tv_series_id: tv_series.id, property_id: "tmdb", value: "4556"})

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
        create_episode(%{season_id: season.id, episode_number: 1, name: "Sample Episode One"})

      create_image(%{
        episode_id: episode1.id,
        role: "thumb",
        content_url: "#{episode1.id}/thumb.jpg",
        extension: "jpg"
      })

      episode2 = create_episode(%{season_id: season.id, episode_number: 2, name: "My Mentor"})

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

      assert {:error, _} = Library.get_tv_series(tv_series.id)
      assert Library.list_seasons!() == []
      assert Library.list_images!() == []
    end

    test "cascade deletes a movie with images and identifiers" do
      movie =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/movies/blade.mkv"
        })

      create_identifier(%{movie_id: movie.id, property_id: "tmdb", value: "78"})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      EntityCascade.destroy!(movie.id)

      assert {:error, _} = Library.get_movie(movie.id)
      assert Library.list_images!() == []
    end
  end
end
