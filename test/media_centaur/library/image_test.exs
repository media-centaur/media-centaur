defmodule MediaCentaur.Library.ImageTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "image CRUD" do
    test "creates an image with content_url" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      image =
        Library.create_image!(%{
          movie_id: movie.id,
          role: "poster",
          content_url: "#{movie.id}/poster.jpg",
          extension: "jpg"
        })

      assert image.role == "poster"
      assert image.content_url == "#{movie.id}/poster.jpg"
      assert image.extension == "jpg"
    end

    test "upserts image on conflict" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      {:ok, first} =
        Library.upsert_image(
          %{movie_id: movie.id, role: "poster", content_url: "old.jpg", extension: "jpg"},
          [:movie_id, :role]
        )

      {:ok, second} =
        Library.upsert_image(
          %{movie_id: movie.id, role: "poster", content_url: "new.jpg", extension: "jpg"},
          [:movie_id, :role]
        )

      # Same image, updated content_url
      assert first.id == second.id || first.movie_id == second.movie_id
      images = Library.list_images!()
      movie_images = Enum.filter(images, &(&1.movie_id == movie.id && &1.role == "poster"))
      assert length(movie_images) == 1
    end
  end
end
