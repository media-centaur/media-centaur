defmodule MediaCentarr.Watcher.FilePresenceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Watcher.FilePresence
  alias MediaCentarr.Watcher.KnownFile
  alias MediaCentarr.Repo

  describe "record_file/2" do
    test "creates a new present record" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")

      file = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie.mkv")
      assert file.state == :present
      assert file.watch_dir == "/media/drive1"
      assert is_nil(file.absent_since)
    end

    test "restores an absent record to present" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")
      FilePresence.mark_files_absent(["/media/drive1/movie.mkv"])

      file = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie.mkv")
      assert file.state == :absent

      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")

      file = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie.mkv")
      assert file.state == :present
      assert is_nil(file.absent_since)
    end

    test "is idempotent — repeated calls do not duplicate or error" do
      Enum.each(1..5, fn _ ->
        FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")
      end)

      rows = Repo.all(from(k in KnownFile, where: k.file_path == "/media/drive1/movie.mkv"))
      assert length(rows) == 1
      assert hd(rows).state == :present
    end
  end

  describe "known_file_paths/1" do
    test "returns file paths for the given watch directory" do
      FilePresence.record_file("/media/drive1/movie1.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/movie2.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive2/movie3.mkv", "/media/drive2")

      paths = FilePresence.known_file_paths("/media/drive1")

      assert MapSet.size(paths) == 2
      assert MapSet.member?(paths, "/media/drive1/movie1.mkv")
      assert MapSet.member?(paths, "/media/drive1/movie2.mkv")
      refute MapSet.member?(paths, "/media/drive2/movie3.mkv")
    end

    test "includes absent files (watcher has seen them)" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")
      FilePresence.mark_files_absent(["/media/drive1/movie.mkv"])

      paths = FilePresence.known_file_paths("/media/drive1")
      assert MapSet.member?(paths, "/media/drive1/movie.mkv")
    end

    test "returns empty set for unknown watch directory" do
      assert MapSet.size(FilePresence.known_file_paths("/nonexistent")) == 0
    end
  end

  describe "mark_absent_for_watch_dir/1" do
    test "marks all present files for a watch dir as absent" do
      FilePresence.record_file("/media/drive1/movie1.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/movie2.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive2/movie3.mkv", "/media/drive2")

      FilePresence.mark_absent_for_watch_dir("/media/drive1")

      drive1_files =
        Repo.all(
          from(k in KnownFile,
            where: k.watch_dir == "/media/drive1",
            order_by: k.file_path
          )
        )

      drive2_file = Repo.get_by!(KnownFile, file_path: "/media/drive2/movie3.mkv")

      assert Enum.all?(drive1_files, &(&1.state == :absent))
      assert Enum.all?(drive1_files, &(not is_nil(&1.absent_since)))
      assert drive2_file.state == :present
    end

    test "is a no-op for empty watch directory" do
      assert :ok = FilePresence.mark_absent_for_watch_dir("/nonexistent")
    end
  end

  describe "mark_files_absent/1" do
    test "marks specific files as absent" do
      FilePresence.record_file("/media/drive1/movie1.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/movie2.mkv", "/media/drive1")

      FilePresence.mark_files_absent(["/media/drive1/movie1.mkv"])

      absent = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie1.mkv")
      present = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie2.mkv")

      assert absent.state == :absent
      refute is_nil(absent.absent_since)
      assert present.state == :present
    end

    test "is a no-op for empty list" do
      assert :ok = FilePresence.mark_files_absent([])
    end
  end

  describe "restore_present_files/2" do
    test "restores absent files found on disk" do
      FilePresence.record_file("/media/drive1/movie1.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/movie2.mkv", "/media/drive1")
      FilePresence.mark_absent_for_watch_dir("/media/drive1")

      # Only movie1 is back on disk
      restored_paths =
        FilePresence.restore_present_files("/media/drive1", ["/media/drive1/movie1.mkv"])

      assert restored_paths == ["/media/drive1/movie1.mkv"]

      restored = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie1.mkv")
      still_absent = Repo.get_by!(KnownFile, file_path: "/media/drive1/movie2.mkv")

      assert restored.state == :present
      assert is_nil(restored.absent_since)
      assert still_absent.state == :absent
    end

    test "returns empty list when no absent files match" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")

      # File is present, not absent — nothing to restore
      assert FilePresence.restore_present_files("/media/drive1", ["/media/drive1/movie.mkv"]) ==
               []
    end

    test "returns empty list with empty paths" do
      assert FilePresence.restore_present_files("/media/drive1", []) == []
    end
  end

  describe "reset_absence_clock_for_dir/1" do
    # Used by AbsencePolicy on watch-dir remount: gives users a fresh
    # full TTL window from the moment the drive becomes visible again,
    # rather than counting absence accumulated while the drive was
    # offline (and we couldn't have verified the file either way).

    test "advances absent_since to now() for every :absent file in the dir" do
      FilePresence.record_file("/media/drive1/movie1.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/movie2.mkv", "/media/drive1")
      FilePresence.mark_absent_for_watch_dir("/media/drive1")

      # Backdate absent_since on both rows so we can confirm the reset
      # actually moves the clock forward.
      old_timestamp = DateTime.add(DateTime.utc_now(), -100, :day)

      Repo.update_all(
        from(k in KnownFile, where: k.watch_dir == "/media/drive1"),
        set: [absent_since: old_timestamp]
      )

      count = FilePresence.reset_absence_clock_for_dir("/media/drive1")
      assert count == 2

      rows = Repo.all(from(k in KnownFile, where: k.watch_dir == "/media/drive1"))

      Enum.each(rows, fn row ->
        assert row.state == :absent
        # The reset must produce a timestamp newer than the one we backdated.
        assert DateTime.after?(row.absent_since, old_timestamp)
      end)
    end

    test "leaves :present rows untouched" do
      FilePresence.record_file("/media/drive1/present.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive1/absent.mkv", "/media/drive1")
      FilePresence.mark_files_absent(["/media/drive1/absent.mkv"])

      FilePresence.reset_absence_clock_for_dir("/media/drive1")

      present_row = Repo.get_by!(KnownFile, file_path: "/media/drive1/present.mkv")
      assert present_row.state == :present
      assert is_nil(present_row.absent_since)
    end

    test "scopes to the named dir — does not touch other dirs" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")
      FilePresence.record_file("/media/drive2/movie.mkv", "/media/drive2")
      FilePresence.mark_files_absent(["/media/drive1/movie.mkv", "/media/drive2/movie.mkv"])

      old_timestamp = DateTime.add(DateTime.utc_now(), -100, :day)

      Repo.update_all(KnownFile, set: [absent_since: old_timestamp])

      FilePresence.reset_absence_clock_for_dir("/media/drive1")

      drive2_row = Repo.get_by!(KnownFile, file_path: "/media/drive2/movie.mkv")
      assert DateTime.compare(drive2_row.absent_since, old_timestamp) == :eq
    end

    test "returns 0 when no absent rows exist for the dir" do
      FilePresence.record_file("/media/drive1/movie.mkv", "/media/drive1")
      assert FilePresence.reset_absence_clock_for_dir("/media/drive1") == 0
    end
  end
end
