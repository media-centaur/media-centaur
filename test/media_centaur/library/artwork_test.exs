defmodule MediaCentaur.Library.ArtworkTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.Library.Artwork

  defp image(owner_type, owner_id, role, content_url),
    do: create_image(%{owner_type: owner_type, owner_id: owner_id, role: role, content_url: content_url})

  describe "urls_by_refs/2 with the poster role" do
    test "resolves a movie's poster image to a /media-images URL" do
      movie = create_movie(%{name: "Movie A"})
      image(:movie, movie.id, "poster", "posters/movie-a.jpg")

      assert Artwork.urls_by_refs([{:movie, movie.id}], "poster") == %{
               {:movie, movie.id} => "/media-images/posters/movie-a.jpg"
             }
    end

    test "resolves an episode to its series' poster" do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 3})
      image(:tv_series, series.id, "poster", "posters/sample-show.jpg")

      assert Artwork.urls_by_refs([{:episode, episode.id}], "poster") == %{
               {:episode, episode.id} => "/media-images/posters/sample-show.jpg"
             }
    end

    test "resolves a video object's poster" do
      video = create_video_object(%{name: "Sample Clip"})
      image(:video_object, video.id, "poster", "posters/sample-clip.jpg")

      assert Artwork.urls_by_refs([{:video_object, video.id}], "poster") == %{
               {:video_object, video.id} => "/media-images/posters/sample-clip.jpg"
             }
    end

    test "omits refs without a poster and refs to deleted entities" do
      movie = create_movie(%{name: "Posterless Movie"})
      image(:movie, movie.id, "backdrop", "backdrops/posterless.jpg")
      missing_id = Ecto.UUID.generate()

      assert Artwork.urls_by_refs([{:movie, movie.id}, {:episode, missing_id}], "poster") == %{}
    end

    test "batches mixed refs in one call" do
      movie = create_movie(%{name: "Movie A"})
      image(:movie, movie.id, "poster", "posters/movie-a.jpg")
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1})
      image(:tv_series, series.id, "poster", "posters/sample-show.jpg")

      assert Artwork.urls_by_refs([{:movie, movie.id}, {:episode, episode.id}], "poster") == %{
               {:movie, movie.id} => "/media-images/posters/movie-a.jpg",
               {:episode, episode.id} => "/media-images/posters/sample-show.jpg"
             }
    end

    test "returns an empty map for no refs" do
      assert Artwork.urls_by_refs([], "poster") == %{}
    end
  end

  describe "urls_by_refs/2 with the backdrop role" do
    test "resolves a movie's backdrop, and an episode to its series' backdrop" do
      movie = create_movie(%{name: "Movie A"})
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 3})
      image(:movie, movie.id, "backdrop", "a/backdrop.jpg")
      image(:movie, movie.id, "poster", "a/poster.jpg")
      image(:tv_series, series.id, "backdrop", "s/backdrop.jpg")

      assert Artwork.urls_by_refs([{:movie, movie.id}, {:episode, episode.id}], "backdrop") == %{
               {:movie, movie.id} => "/media-images/a/backdrop.jpg",
               {:episode, episode.id} => "/media-images/s/backdrop.jpg"
             }
    end

    test "a role the entity lacks is simply absent" do
      movie = create_movie(%{name: "Movie A"})
      image(:movie, movie.id, "poster", "a/poster.jpg")

      assert Artwork.urls_by_refs([{:movie, movie.id}], "backdrop") == %{}
    end
  end

  describe "urls_by_refs/2 with the logo role" do
    test "resolves a series' logo by its ref" do
      series = create_tv_series(%{name: "Sample Show"})
      image(:tv_series, series.id, "logo", "s/logo.png")

      assert Artwork.urls_by_refs([{:tv_series, series.id}], "logo") == %{
               {:tv_series, series.id} => "/media-images/s/logo.png"
             }
    end
  end

  test "a role outside poster, backdrop and logo is refused" do
    assert_raise FunctionClauseError, fn ->
      Artwork.urls_by_refs([{:movie, Ecto.UUID.generate()}], "still")
    end
  end
end
