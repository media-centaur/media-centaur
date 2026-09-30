defmodule MediaCentaur.Library.ImagesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Images

  # ---------------------------------------------------------------------------
  # Image ready (from image pipeline)
  # ---------------------------------------------------------------------------

  describe "ready/1" do
    test "creates image record for movie owner" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      Images.ready(%{
        owner_id: movie.id,
        owner_type: "movie",
        role: "poster",
        content_url: "images/#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      movie = MediaCentaur.Repo.preload(movie, :images)
      assert [image] = movie.images
      assert image.role == "poster"
      assert image.content_url == "images/#{movie.id}/poster.jpg"
      assert image.owner_type == :movie
      assert image.owner_id == movie.id
    end

    test "creates image record for child movie owner" do
      series = create_entity(%{type: :movie_series, name: "Collection"})

      {:ok, movie} =
        Library.Containers.find_or_create_movie_for_series(%{
          movie_series_id: series.id,
          tmdb_id: "155",
          name: "Movie",
          position: 1
        })

      Images.ready(%{
        owner_id: movie.id,
        owner_type: "movie",
        role: "poster",
        content_url: "images/#{series.id}/movie_poster.jpg",
        extension: "jpg"
      })

      movie = MediaCentaur.Repo.preload(movie, :images)
      assert [image] = movie.images
      assert image.role == "poster"
      assert image.owner_type == :movie
      assert image.owner_id == movie.id
    end
  end
end
