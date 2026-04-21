defmodule MediaCentarr.Library.WatchedFileTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library

  describe "WatchedFile :link_file action" do
    test "creates record with movie_id" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      assert {:ok, file} =
               Library.link_file(%{
                 file_path: "/media/test/linked.mkv",
                 watch_dir: "/media/test",
                 movie_id: movie.id
               })

      assert file.movie_id == movie.id
      assert file.file_path == "/media/test/linked.mkv"
      assert file.watch_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      movie1 = create_entity(%{type: :movie, name: "First Movie"})
      movie2 = create_entity(%{type: :movie, name: "Second Movie"})

      {:ok, first} =
        Library.link_file(%{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          movie_id: movie1.id
        })

      {:ok, second} =
        Library.link_file(%{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          movie_id: movie2.id
        })

      assert first.id == second.id

      # Only one record exists
      all = Library.list_watched_files()
      assert length(all) == 1
    end
  end
end
