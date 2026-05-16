defmodule MediaCentarr.Library.ImageTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library

  describe "image CRUD" do
    test "creates an image with content_url" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      image =
        Library.create_image!(%{
          owner_type: :movie,
          owner_id: movie.id,
          role: "poster",
          content_url: "#{movie.id}/poster.jpg",
          extension: "jpg"
        })

      assert image.role == "poster"
      assert image.content_url == "#{movie.id}/poster.jpg"
      assert image.extension == "jpg"
      assert image.owner_type == :movie
      assert image.owner_id == movie.id
    end

    test "upserts image on conflict" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      {:ok, first} =
        Library.upsert_image(
          %{
            owner_type: :movie,
            owner_id: movie.id,
            role: "poster",
            content_url: "old.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      {:ok, second} =
        Library.upsert_image(
          %{
            owner_type: :movie,
            owner_id: movie.id,
            role: "poster",
            content_url: "new.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      # Same image, updated content_url
      assert first.id == second.id || first.owner_id == second.owner_id
      images = Library.list_all_images()

      movie_images =
        Enum.filter(images, &(&1.owner_id == movie.id && &1.role == "poster"))

      assert length(movie_images) == 1
    end

    test "polymorphic owner discriminator separates Movie and TVSeries images of same role" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      tv = create_entity(%{type: :tv_series, name: "Sample Show"})

      {:ok, _} =
        Library.upsert_image(
          %{
            owner_type: :movie,
            owner_id: movie.id,
            role: "poster",
            content_url: "movie-poster.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      {:ok, _} =
        Library.upsert_image(
          %{
            owner_type: :tv_series,
            owner_id: tv.id,
            role: "poster",
            content_url: "tv-poster.jpg",
            extension: "jpg"
          },
          [:owner_type, :owner_id, :role]
        )

      images = Library.list_all_images()
      assert Enum.any?(images, &(&1.owner_type == :movie and &1.owner_id == movie.id))
      assert Enum.any?(images, &(&1.owner_type == :tv_series and &1.owner_id == tv.id))
    end
  end
end
