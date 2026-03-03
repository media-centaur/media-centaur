defmodule MediaCentaur.Library.ImageTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "pending_download action" do
    test "returns images with url but no content_url" do
      entity = create_entity(%{type: :movie, name: "Missing Poster"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        extension: "jpg"
      })

      pending = Library.list_pending_downloads!()

      assert length(pending) == 1
      assert hd(pending).role == "poster"
      assert hd(pending).url != nil
      assert hd(pending).content_url == nil
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

      pending = Library.list_pending_downloads!()

      assert pending == []
    end

    test "excludes images with no url" do
      entity = create_entity(%{type: :movie, name: "No URL"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        extension: "jpg"
      })

      pending = Library.list_pending_downloads!()

      assert pending == []
    end

    test "preloads the parent entity" do
      entity = create_entity(%{type: :movie, name: "With Entity"})

      create_image(%{
        entity_id: entity.id,
        role: "backdrop",
        url: "https://image.tmdb.org/t/p/original/backdrop.jpg",
        extension: "jpg"
      })

      [image] = Library.list_pending_downloads!()

      assert image.entity != nil
      assert image.entity.name == "With Entity"
    end
  end
end
