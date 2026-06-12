defmodule MediaCentaur.Library.PostersTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Library.Posters

  describe "urls_by_refs/1" do
    test "resolves a movie's poster image to a /media-images URL" do
      movie = create_movie(%{name: "Movie A"})

      create_image(%{
        owner_type: :movie,
        owner_id: movie.id,
        role: "poster",
        content_url: "posters/movie-a.jpg"
      })

      assert Posters.urls_by_refs([{:movie, movie.id}]) == %{
               {:movie, movie.id} => "/media-images/posters/movie-a.jpg"
             }
    end

    test "resolves an episode to its series' poster" do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 3})

      create_image(%{
        owner_type: :tv_series,
        owner_id: series.id,
        role: "poster",
        content_url: "posters/sample-show.jpg"
      })

      assert Posters.urls_by_refs([{:episode, episode.id}]) == %{
               {:episode, episode.id} => "/media-images/posters/sample-show.jpg"
             }
    end

    test "resolves a video object's poster" do
      video = create_video_object(%{name: "Sample Clip"})

      create_image(%{
        owner_type: :video_object,
        owner_id: video.id,
        role: "poster",
        content_url: "posters/sample-clip.jpg"
      })

      assert Posters.urls_by_refs([{:video_object, video.id}]) == %{
               {:video_object, video.id} => "/media-images/posters/sample-clip.jpg"
             }
    end

    test "omits refs without a poster and refs to deleted entities" do
      movie = create_movie(%{name: "Posterless Movie"})

      create_image(%{
        owner_type: :movie,
        owner_id: movie.id,
        role: "backdrop",
        content_url: "backdrops/posterless.jpg"
      })

      missing_id = Ecto.UUID.generate()

      assert Posters.urls_by_refs([{:movie, movie.id}, {:episode, missing_id}]) == %{}
    end

    test "batches mixed refs in one call" do
      movie = create_movie(%{name: "Movie A"})

      create_image(%{
        owner_type: :movie,
        owner_id: movie.id,
        role: "poster",
        content_url: "posters/movie-a.jpg"
      })

      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1})

      create_image(%{
        owner_type: :tv_series,
        owner_id: series.id,
        role: "poster",
        content_url: "posters/sample-show.jpg"
      })

      result = Posters.urls_by_refs([{:movie, movie.id}, {:episode, episode.id}])

      assert result == %{
               {:movie, movie.id} => "/media-images/posters/movie-a.jpg",
               {:episode, episode.id} => "/media-images/posters/sample-show.jpg"
             }
    end

    test "returns an empty map for no refs" do
      assert Posters.urls_by_refs([]) == %{}
    end
  end
end
