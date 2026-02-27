defmodule MediaManager.Library.WatchedFileTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchedFile

  describe "WatchedFile :link_file action" do
    test "creates record with entity_id and state :complete" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:link_file, %{
                 file_path: "/media/test/linked.mkv",
                 watch_dir: "/media/test",
                 entity_id: entity.id
               })
               |> Ash.create()

      assert file.state == :complete
      assert file.entity_id == entity.id
      assert file.file_path == "/media/test/linked.mkv"
      assert file.watch_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      entity1 = create_entity(%{type: :movie, name: "First Movie"})
      entity2 = create_entity(%{type: :movie, name: "Second Movie"})

      {:ok, first} =
        WatchedFile
        |> Ash.Changeset.for_create(:link_file, %{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          entity_id: entity1.id
        })
        |> Ash.create()

      {:ok, second} =
        WatchedFile
        |> Ash.Changeset.for_create(:link_file, %{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          entity_id: entity2.id
        })
        |> Ash.create()

      assert first.id == second.id
      assert second.state == :complete

      # Only one record exists
      all = Ash.read!(WatchedFile)
      assert length(all) == 1
    end
  end
end
