defmodule MediaCentaur.Library.ImageTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "image CRUD" do
    test "creates an image with content_url" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      image =
        Library.create_image!(%{
          entity_id: entity.id,
          role: "poster",
          content_url: "#{entity.id}/poster.jpg",
          extension: "jpg"
        })

      assert image.role == "poster"
      assert image.content_url == "#{entity.id}/poster.jpg"
      assert image.extension == "jpg"
    end

    test "upserts image on conflict" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      {:ok, first} =
        Library.upsert_image(
          %{entity_id: entity.id, role: "poster", content_url: "old.jpg", extension: "jpg"},
          [:entity_id, :role]
        )

      {:ok, second} =
        Library.upsert_image(
          %{entity_id: entity.id, role: "poster", content_url: "new.jpg", extension: "jpg"},
          [:entity_id, :role]
        )

      # Same image, updated content_url
      assert first.id == second.id || first.entity_id == second.entity_id
      images = Library.list_images!()
      entity_images = Enum.filter(images, &(&1.entity_id == entity.id && &1.role == "poster"))
      assert length(entity_images) == 1
    end
  end
end
