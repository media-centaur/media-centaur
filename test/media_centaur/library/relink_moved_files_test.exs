defmodule MediaCentaur.Library.RelinkMovedFilesTest do
  @moduledoc """
  `Library.relink_moved_files/3` — the stateful half of relink-on-move.
  Given newly-seen `{path, size}` pairs under a watch dir, it re-points the
  existing entity's file rows (WatchedFile / ExtraFile) and the FilePresence
  ledger to the new location instead of letting the file re-import as new.

  The only filesystem dependency — "is the old path still on disk?" — is
  injected via `:exists?`, so these are deterministic with no real I/O.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.FilePresence

  import MediaCentaur.TestFactory

  defp linked_movie_file(file_path, watch_dir, size) do
    movie = create_standalone_movie(%{name: "Movie #{System.unique_integer([:positive])}"})
    file = create_linked_file(%{movie_id: movie.id, watch_dir: watch_dir, file_path: file_path})
    # create_linked_file stamps presence size-less; record the size the move
    # matcher needs.
    _ = FilePresence.stamp(file_path, watch_dir, DateTime.utc_now(), size: size)
    {movie, file}
  end

  describe "relink_moved_files/3" do
    test "re-points the file rows and presence ledger when a file moved (old path gone)" do
      {_movie, _file} = linked_movie_file("/old/Movies/foo/foo.mkv", "/old", 1000)

      result =
        Library.relink_moved_files([{"/new/Movies/foo/foo.mkv", 1000}], "/new",
          exists?: fn _ -> false end
        )

      assert result == %{relinked: ["/new/Movies/foo/foo.mkv"], still_new: []}

      # WatchedFile now resolves at the new path; old path is gone.
      assert [watched] = Library.list_files_by_paths(["/new/Movies/foo/foo.mkv"])
      assert watched.watch_dir == "/new"
      assert Library.list_files_by_paths(["/old/Movies/foo/foo.mkv"]) == []

      # Presence ledger re-pointed (this is what stops a re-scan re-importing).
      assert "/new/Movies/foo/foo.mkv" in FilePresence.list_paths_for_watch_dir("/new")
      assert Enum.empty?(FilePresence.list_paths_for_watch_dir("/old"))
    end

    test "treats a copy (old path still present) as still-new and changes nothing" do
      {_movie, _file} = linked_movie_file("/old/Movies/foo/foo.mkv", "/old", 1000)

      result =
        Library.relink_moved_files([{"/new/Movies/foo/foo.mkv", 1000}], "/new",
          exists?: fn _ -> true end
        )

      assert result == %{relinked: [], still_new: ["/new/Movies/foo/foo.mkv"]}
      assert [watched] = Library.list_files_by_paths(["/old/Movies/foo/foo.mkv"])
      assert watched.watch_dir == "/old"
    end

    test "ambiguous match (two candidates share relative path + size) bails to still-new" do
      {_m1, _f1} = linked_movie_file("/a/Movies/foo.mkv", "/a", 1000)
      {_m2, _f2} = linked_movie_file("/c/Movies/foo.mkv", "/c", 1000)

      result =
        Library.relink_moved_files([{"/new/Movies/foo.mkv", 1000}], "/new", exists?: fn _ -> false end)

      assert result == %{relinked: [], still_new: ["/new/Movies/foo.mkv"]}
    end

    test "does not create or duplicate entities — a move re-points, it does not re-import" do
      {_movie, _file} = linked_movie_file("/old/Movies/foo.mkv", "/old", 1000)
      before_count = Repo.aggregate(MediaCentaur.Library.Movie, :count)

      Library.relink_moved_files([{"/new/Movies/foo.mkv", 1000}], "/new", exists?: fn _ -> false end)

      assert Repo.aggregate(MediaCentaur.Library.Movie, :count) == before_count
    end

    test "empty input is a no-op" do
      assert Library.relink_moved_files([], "/new") == %{relinked: [], still_new: []}
    end
  end
end
