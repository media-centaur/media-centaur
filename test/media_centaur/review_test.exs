defmodule MediaCentaur.ReviewTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Review

  setup do
    media_dir = Path.join(System.tmp_dir!(), "review_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(media_dir)
    on_exit(fn -> File.rm_rf!(media_dir) end)

    %{media_dir: media_dir}
  end

  describe "delete_pending_file/1" do
    test "removes the file from disk, its FilePresence row, and the PendingFile row", %{
      media_dir: media_dir
    } do
      path = Path.join(media_dir, "broken_release.mkv")
      File.write!(path, "garbage")
      FilePresence.stamp(path, media_dir)

      pending_file =
        create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Broken"})

      assert {:ok, _} = Review.delete_pending_file(pending_file)

      refute File.exists?(path)
      refute MapSet.member?(FilePresence.list_paths_for_media_dir(media_dir), path)
      assert Review.fetch_pending_file(pending_file.id) == {:error, :not_found}
    end

    test "treats an already-missing file as success — the DB cleanup still runs", %{
      media_dir: media_dir
    } do
      path = Path.join(media_dir, "already_gone.mkv")

      pending_file =
        create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Gone"})

      assert {:ok, _} = Review.delete_pending_file(pending_file)
      assert Review.fetch_pending_file(pending_file.id) == {:error, :not_found}
    end
  end

  describe "delete_group/1" do
    test "deletes every file in the group and reports counts", %{media_dir: media_dir} do
      paths =
        for name <- ["a.mkv", "b.mkv"] do
          path = Path.join(media_dir, name)
          File.write!(path, "x")
          path
        end

      files =
        Enum.map(paths, fn path ->
          create_pending_file(%{file_path: path, media_directory: media_dir, parsed_title: "Group"})
        end)

      assert {2, 0} = Review.delete_group(files)
      assert Enum.all?(paths, &(not File.exists?(&1)))
    end
  end
end
