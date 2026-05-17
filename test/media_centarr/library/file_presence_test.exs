defmodule MediaCentarr.Library.FilePresenceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.FilePresence
  alias MediaCentarr.Repo

  describe "stamp/3" do
    test "inserts a new presence row for an unseen path" do
      now = DateTime.utc_now()

      presence = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", now)

      assert presence.id
      assert presence.file_path == "/media/movies/sample.mkv"
      assert presence.watch_dir == "/media/movies"
      assert DateTime.compare(presence.last_seen_at, now) == :eq

      assert Repo.aggregate(FilePresence, :count) == 1
    end

    test "updates last_seen_at when the same path is restamped" do
      then_ = DateTime.add(DateTime.utc_now(), -3600, :second)
      now = DateTime.utc_now()

      _first = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", then_)
      second = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", now)

      assert Repo.aggregate(FilePresence, :count) == 1
      assert DateTime.compare(second.last_seen_at, now) == :eq
    end

    test "updates watch_dir if a path moves between watch roots" do
      _first = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies")
      moved = FilePresence.stamp("/media/movies/sample.mkv", "/media/extra")

      assert moved.watch_dir == "/media/extra"
      assert Repo.aggregate(FilePresence, :count) == 1
    end
  end

  describe "stamp_many/3" do
    test "inserts every path in a single roundtrip" do
      paths = for n <- 1..50, do: "/media/movies/file_#{n}.mkv"

      count = FilePresence.stamp_many(paths, "/media/movies")

      assert count == 50
      assert Repo.aggregate(FilePresence, :count) == 50
    end

    test "upserts existing paths in the bulk call" do
      now = DateTime.utc_now()
      then_ = DateTime.add(now, -3600, :second)

      FilePresence.stamp("/media/movies/a.mkv", "/media/movies", then_)
      FilePresence.stamp("/media/movies/b.mkv", "/media/movies", then_)

      count =
        FilePresence.stamp_many(
          ["/media/movies/a.mkv", "/media/movies/b.mkv", "/media/movies/c.mkv"],
          "/media/movies",
          now
        )

      # All three rows present (a + b refreshed, c inserted).
      assert count == 3
      assert Repo.aggregate(FilePresence, :count) == 3

      [a, b, c] = Enum.sort_by(Repo.all(FilePresence), & &1.file_path)
      assert DateTime.compare(a.last_seen_at, now) == :eq
      assert DateTime.compare(b.last_seen_at, now) == :eq
      assert DateTime.compare(c.last_seen_at, now) == :eq
    end

    test "no-op on empty list" do
      assert FilePresence.stamp_many([], "/media/movies") == 0
      assert Repo.aggregate(FilePresence, :count) == 0
    end
  end

  describe "list_paths_for_watch_dir/1" do
    test "returns only paths in the given watch directory" do
      FilePresence.stamp("/media/movies/a.mkv", "/media/movies")
      FilePresence.stamp("/media/movies/b.mkv", "/media/movies")
      FilePresence.stamp("/media/tv/series/c.mkv", "/media/tv")

      paths = FilePresence.list_paths_for_watch_dir("/media/movies")

      assert MapSet.size(paths) == 2
      assert MapSet.member?(paths, "/media/movies/a.mkv")
      assert MapSet.member?(paths, "/media/movies/b.mkv")
      refute MapSet.member?(paths, "/media/tv/series/c.mkv")
    end

    test "returns empty set when no paths tracked" do
      assert MapSet.size(FilePresence.list_paths_for_watch_dir("/nope")) == 0
    end
  end

  describe "list_stale/1" do
    test "returns rows older than the threshold" do
      old = DateTime.add(DateTime.utc_now(), -7200, :second)
      now = DateTime.utc_now()
      threshold = DateTime.add(DateTime.utc_now(), -3600, :second)

      FilePresence.stamp("/media/movies/old.mkv", "/media/movies", old)
      FilePresence.stamp("/media/movies/fresh.mkv", "/media/movies", now)

      stale = FilePresence.list_stale(threshold)

      assert Enum.map(stale, & &1.file_path) == ["/media/movies/old.mkv"]
    end

    test "threshold boundary excludes rows stamped exactly at the threshold" do
      threshold = DateTime.utc_now()

      FilePresence.stamp("/media/movies/exact.mkv", "/media/movies", threshold)

      assert FilePresence.list_stale(threshold) == []
    end
  end

  describe "delete_paths/1" do
    test "removes the named paths and returns the count" do
      FilePresence.stamp("/media/movies/keep.mkv", "/media/movies")
      FilePresence.stamp("/media/movies/drop_a.mkv", "/media/movies")
      FilePresence.stamp("/media/movies/drop_b.mkv", "/media/movies")

      deleted =
        FilePresence.delete_paths([
          "/media/movies/drop_a.mkv",
          "/media/movies/drop_b.mkv"
        ])

      assert deleted == 2
      assert Repo.aggregate(FilePresence, :count) == 1

      [remaining] = Repo.all(FilePresence)
      assert remaining.file_path == "/media/movies/keep.mkv"
    end

    test "no-op on empty list" do
      FilePresence.stamp("/media/movies/keep.mkv", "/media/movies")

      assert FilePresence.delete_paths([]) == 0
      assert Repo.aggregate(FilePresence, :count) == 1
    end
  end
end
