defmodule MediaCentaur.Library.RelinkMovedFilesTest do
  @moduledoc """
  `Library.Relink.moved_files/3` — the stateful half of relink-on-move.
  Given newly-seen `{path, size}` pairs under a media dir, it re-points the
  existing entity's file rows (WatchedFile / ExtraFile) and the FilePresence
  ledger to the new location instead of letting the file re-import as new.

  The only filesystem dependency — "is the old path still on disk?" — is
  injected via `:exists?`, so these are deterministic with no real I/O.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.FilePresence

  import MediaCentaur.TestFactory

  defp linked_movie_file(file_path, media_dir, size) do
    movie = create_standalone_movie(%{name: "Movie #{System.unique_integer([:positive])}"})
    file = create_linked_file(%{movie_id: movie.id, media_dir: media_dir, file_path: file_path})
    # create_linked_file stamps presence size-less; record the size the move
    # matcher needs.
    _ = FilePresence.stamp(file_path, media_dir, DateTime.utc_now(), size: size)
    {movie, file}
  end

  describe "relink_moved_files/3" do
    test "re-points the file rows and presence ledger when a file moved (old path gone)" do
      {_movie, _file} = linked_movie_file("/old/Movies/foo/foo.mkv", "/old", 1000)

      result =
        Library.Relink.moved_files([{"/new/Movies/foo/foo.mkv", 1000}], "/new",
          exists?: fn _ -> false end
        )

      assert result == %{relinked: ["/new/Movies/foo/foo.mkv"], still_new: []}

      # WatchedFile now resolves at the new path; old path is gone.
      assert [watched] = Library.Files.list_by_paths(["/new/Movies/foo/foo.mkv"])
      assert watched.media_dir == "/new"
      assert Library.Files.list_by_paths(["/old/Movies/foo/foo.mkv"]) == []

      # Presence ledger re-pointed (this is what stops a re-scan re-importing).
      assert "/new/Movies/foo/foo.mkv" in FilePresence.list_paths_for_media_dir("/new")
      assert Enum.empty?(FilePresence.list_paths_for_media_dir("/old"))
    end

    test "treats a copy (old path still present) as still-new and changes nothing" do
      {_movie, _file} = linked_movie_file("/old/Movies/foo/foo.mkv", "/old", 1000)

      result =
        Library.Relink.moved_files([{"/new/Movies/foo/foo.mkv", 1000}], "/new",
          exists?: fn _ -> true end
        )

      assert result == %{relinked: [], still_new: ["/new/Movies/foo/foo.mkv"]}
      assert [watched] = Library.Files.list_by_paths(["/old/Movies/foo/foo.mkv"])
      assert watched.media_dir == "/old"
    end

    test "ambiguous match (two candidates share relative path + size) bails to still-new" do
      {_m1, _f1} = linked_movie_file("/a/Movies/foo.mkv", "/a", 1000)
      {_m2, _f2} = linked_movie_file("/c/Movies/foo.mkv", "/c", 1000)

      result =
        Library.Relink.moved_files([{"/new/Movies/foo.mkv", 1000}], "/new", exists?: fn _ -> false end)

      assert result == %{relinked: [], still_new: ["/new/Movies/foo.mkv"]}
    end

    test "does not create or duplicate entities — a move re-points, it does not re-import" do
      {_movie, _file} = linked_movie_file("/old/Movies/foo.mkv", "/old", 1000)
      before_count = Repo.aggregate(MediaCentaur.Library.Movie, :count)

      Library.Relink.moved_files([{"/new/Movies/foo.mkv", 1000}], "/new", exists?: fn _ -> false end)

      assert Repo.aggregate(MediaCentaur.Library.Movie, :count) == before_count
    end

    test "empty input is a no-op" do
      assert Library.Relink.moved_files([], "/new") == %{relinked: [], still_new: []}
    end
  end

  # The reproduction harness for the original bug report. Unit tests above
  # inject `exists?`; these drive the *real* filesystem (a real File.rename)
  # with the default check, so they prove the move-vs-copy disambiguation
  # against actual files — the part that can't be reproduced on the shared
  # prod DB. Pre-relink, the moved file imported as a new/orphaned entity;
  # these go red on that code and green with relink.
  describe "real filesystem (default exists? check)" do
    setup do
      base = Path.join(System.tmp_dir!(), "relink_#{System.unique_integer([:positive])}")
      rel = "Movies/foo/foo.mkv"
      old_dir = Path.join(base, "A")
      new_dir = Path.join(base, "B")
      old_path = Path.join(old_dir, rel)
      new_path = Path.join(new_dir, rel)

      File.mkdir_p!(Path.dirname(old_path))
      File.write!(old_path, "the-bytes-of-a-movie")
      size = File.stat!(old_path).size

      movie = create_standalone_movie(%{name: "Realfs Movie"})
      _ = create_linked_file(%{movie_id: movie.id, media_dir: old_dir, file_path: old_path})
      _ = FilePresence.stamp(old_path, old_dir, DateTime.utc_now(), size: size)

      File.mkdir_p!(Path.dirname(new_path))
      on_exit(fn -> File.rm_rf!(base) end)

      %{old_dir: old_dir, new_dir: new_dir, old_path: old_path, new_path: new_path, size: size}
    end

    test "a file renamed to a new dir is relinked, not re-imported", ctx do
      :ok = File.rename(ctx.old_path, ctx.new_path)
      before_movies = Repo.aggregate(MediaCentaur.Library.Movie, :count)

      result = Library.Relink.moved_files([{ctx.new_path, ctx.size}], ctx.new_dir)

      assert result == %{relinked: [ctx.new_path], still_new: []}
      assert [watched] = Library.Files.list_by_paths([ctx.new_path])
      assert watched.media_dir == ctx.new_dir
      assert Library.Files.list_by_paths([ctx.old_path]) == []
      assert Repo.aggregate(MediaCentaur.Library.Movie, :count) == before_movies
    end

    test "a copy (original still on disk) is left to import as new", ctx do
      File.cp!(ctx.old_path, ctx.new_path)

      result = Library.Relink.moved_files([{ctx.new_path, ctx.size}], ctx.new_dir)

      assert result == %{relinked: [], still_new: [ctx.new_path]}
      assert [watched] = Library.Files.list_by_paths([ctx.old_path])
      assert watched.media_dir == ctx.old_dir
    end
  end
end
