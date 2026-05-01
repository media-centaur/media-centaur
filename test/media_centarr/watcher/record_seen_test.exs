defmodule MediaCentarr.Watcher.RecordSeenTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.WatchedFile
  alias MediaCentarr.Watcher
  alias MediaCentarr.Watcher.KnownFile

  describe "record_seen/1" do
    test "writes both library_watched_files and watcher_files atomically" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})

      attrs = %{
        file_path: "/media/movies/sample.mkv",
        watch_dir: "/media/movies",
        movie_id: movie.id
      }

      assert {:ok, %WatchedFile{} = file} = Watcher.record_seen(attrs)
      assert file.movie_id == movie.id
      assert file.file_path == "/media/movies/sample.mkv"

      known = Repo.get_by!(KnownFile, file_path: "/media/movies/sample.mkv")
      assert known.state == :present
      assert known.watch_dir == "/media/movies"
    end

    test "is idempotent — repeated calls do not duplicate rows" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})

      attrs = %{
        file_path: "/media/movies/sample.mkv",
        watch_dir: "/media/movies",
        movie_id: movie.id
      }

      assert {:ok, _} = Watcher.record_seen(attrs)
      assert {:ok, _} = Watcher.record_seen(attrs)
      assert {:ok, _} = Watcher.record_seen(attrs)

      assert length(Library.list_watched_files()) == 1
      assert Repo.aggregate(KnownFile, :count) == 1
    end

    test "rolls back KnownFile write if link_file fails" do
      # Force a validation failure: empty file_path triggers the
      # validate_required check on WatchedFile.link_file_changeset/1.
      attrs = %{
        file_path: "",
        watch_dir: "/media/movies"
      }

      assert {:error, _} = Watcher.record_seen(attrs)

      assert Library.list_watched_files() == []
      assert Repo.aggregate(KnownFile, :count) == 0
    end
  end
end
