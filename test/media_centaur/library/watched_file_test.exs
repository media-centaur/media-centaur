defmodule MediaCentaur.Library.WatchedFileTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library

  describe "WatchedFile :link_file action" do
    test "creates record with entity_id" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      assert {:ok, file} =
               Library.link_file(%{
                 file_path: "/media/test/linked.mkv",
                 watch_dir: "/media/test",
                 entity_id: entity.id
               })

      assert file.entity_id == entity.id
      assert file.file_path == "/media/test/linked.mkv"
      assert file.watch_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      entity1 = create_entity(%{type: :movie, name: "First Movie"})
      entity2 = create_entity(%{type: :movie, name: "Second Movie"})

      {:ok, first} =
        Library.link_file(%{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          entity_id: entity1.id
        })

      {:ok, second} =
        Library.link_file(%{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          entity_id: entity2.id
        })

      assert first.id == second.id

      # Only one record exists
      all = Library.list_watched_files!()
      assert length(all) == 1
    end
  end
end
