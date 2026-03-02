defmodule MediaCentaur.Library.ImageTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "incomplete action" do
    test "returns images with url but no content_url" do
      entity = create_entity(%{type: :movie, name: "Missing Poster"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        extension: "jpg"
      })

      incomplete = Library.list_incomplete_images!()

      assert length(incomplete) == 1
      assert hd(incomplete).role == "poster"
      assert hd(incomplete).url != nil
      assert hd(incomplete).content_url == nil
    end

    test "excludes images that have been downloaded" do
      entity = create_entity(%{type: :movie, name: "Complete Images"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        content_url: "#{entity.id}/poster.jpg",
        extension: "jpg"
      })

      incomplete = Library.list_incomplete_images!()

      assert incomplete == []
    end

    test "excludes images with no url" do
      entity = create_entity(%{type: :movie, name: "No URL"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        extension: "jpg"
      })

      incomplete = Library.list_incomplete_images!()

      assert incomplete == []
    end

    test "preloads the parent entity" do
      entity = create_entity(%{type: :movie, name: "With Entity"})

      create_image(%{
        entity_id: entity.id,
        role: "backdrop",
        url: "https://image.tmdb.org/t/p/original/backdrop.jpg",
        extension: "jpg"
      })

      [image] = Library.list_incomplete_images!()

      assert image.entity != nil
      assert image.entity.name == "With Entity"
    end
  end
end
