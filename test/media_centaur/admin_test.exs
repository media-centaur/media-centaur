defmodule MediaCentaur.AdminTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Admin
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Review.PendingFile

  import MediaCentaur.TestFactory

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Ash.read!(PendingFile, action: :read)

      Admin.clear_database()

      assert [] = Ash.read!(PendingFile, action: :read)
    end
  end

  describe "dismiss_incomplete_images/0" do
    test "deletes images with url but no content_url" do
      entity = create_entity(%{type: :movie, name: "Missing Poster"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, 1} = Admin.dismiss_incomplete_images()

      assert [] = Ash.read!(Image)
    end

    test "preserves images that have been downloaded" do
      entity = create_entity(%{type: :movie, name: "Complete Images"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        content_url: "#{entity.id}/poster.jpg",
        extension: "jpg"
      })

      assert {:ok, 0} = Admin.dismiss_incomplete_images()

      assert [_] = Ash.read!(Image)
    end

    test "returns zero when no incomplete images exist" do
      assert {:ok, 0} = Admin.dismiss_incomplete_images()
    end

    test "deletes only incomplete images when mixed" do
      entity = create_entity(%{type: :movie, name: "Mixed Images"})

      create_image(%{
        entity_id: entity.id,
        role: "poster",
        url: "https://image.tmdb.org/t/p/original/poster.jpg",
        content_url: "#{entity.id}/poster.jpg",
        extension: "jpg"
      })

      create_image(%{
        entity_id: entity.id,
        role: "backdrop",
        url: "https://image.tmdb.org/t/p/original/backdrop.jpg",
        extension: "jpg"
      })

      assert {:ok, 1} = Admin.dismiss_incomplete_images()

      remaining = Ash.read!(Image)
      assert length(remaining) == 1
      assert hd(remaining).role == "poster"
    end
  end
end
