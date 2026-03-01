defmodule MediaCentaur.Library.WatchedFileTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Library.WatchedFile

  describe "WatchedFile :mark_absent action" do
    test "transitions state to :absent and sets absent_since" do
      entity = create_entity()
      file = create_linked_file(%{entity: entity})
      assert file.state == :complete
      assert is_nil(file.absent_since)

      {:ok, absent_file} =
        file
        |> Ash.Changeset.for_update(:mark_absent, %{})
        |> Ash.update()

      assert absent_file.state == :absent
      assert %DateTime{} = absent_file.absent_since
    end
  end

  describe "WatchedFile :mark_present action" do
    test "transitions state to :complete and clears absent_since" do
      entity = create_entity()
      file = create_linked_file(%{entity: entity})

      {:ok, absent_file} =
        file
        |> Ash.Changeset.for_update(:mark_absent, %{})
        |> Ash.update()

      assert absent_file.state == :absent

      {:ok, restored_file} =
        absent_file
        |> Ash.Changeset.for_update(:mark_present, %{})
        |> Ash.update()

      assert restored_file.state == :complete
      assert is_nil(restored_file.absent_since)
    end
  end

  describe "WatchedFile :expired_absent read action" do
    test "returns absent files older than cutoff" do
      entity = create_entity()
      file = create_linked_file(%{entity: entity})

      # Mark absent with a timestamp in the past
      past = DateTime.add(DateTime.utc_now(), -31, :day)

      {:ok, absent_file} =
        file
        |> Ash.Changeset.for_update(:mark_absent, %{})
        |> Ash.update()

      # Manually set absent_since to the past for testing
      {:ok, _} =
        absent_file
        |> Ash.Changeset.for_update(:set_absent_since, %{absent_since: past})
        |> Ash.update()

      cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      expired =
        WatchedFile
        |> Ash.Query.for_read(:expired_absent, %{cutoff: cutoff})
        |> Ash.read!()

      assert length(expired) == 1
      assert hd(expired).file_path == file.file_path
    end

    test "excludes absent files newer than cutoff" do
      entity = create_entity()
      file = create_linked_file(%{entity: entity})

      {:ok, _} =
        file
        |> Ash.Changeset.for_update(:mark_absent, %{})
        |> Ash.update()

      cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      expired =
        WatchedFile
        |> Ash.Query.for_read(:expired_absent, %{cutoff: cutoff})
        |> Ash.read!()

      assert expired == []
    end

    test "excludes complete files" do
      entity = create_entity()
      _file = create_linked_file(%{entity: entity})

      cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

      expired =
        WatchedFile
        |> Ash.Query.for_read(:expired_absent, %{cutoff: cutoff})
        |> Ash.read!()

      assert expired == []
    end
  end

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
