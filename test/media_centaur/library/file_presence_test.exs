defmodule MediaCentaur.Library.FilePresenceTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Repo

  describe "total_size_bytes/0" do
    test "sums the recorded sizes of all presence rows" do
      FilePresence.stamp("/media/a.mkv", "/media", DateTime.utc_now(), size: 1_000)
      FilePresence.stamp("/media/b.mkv", "/media", DateTime.utc_now(), size: 2_500)

      assert FilePresence.total_size_bytes() == 3_500
    end

    test "treats rows with a nil size as zero" do
      FilePresence.stamp("/media/a.mkv", "/media", DateTime.utc_now(), size: 1_000)
      FilePresence.stamp("/media/sizeless.mkv", "/media", DateTime.utc_now())

      assert FilePresence.total_size_bytes() == 1_000
    end

    test "returns zero when there are no presence rows" do
      assert FilePresence.total_size_bytes() == 0
    end
  end

  describe "stamp/3" do
    test "inserts a new presence row for an unseen path" do
      now = DateTime.utc_now()

      presence = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", now)

      assert presence.id
      assert presence.file_path == "/media/movies/sample.mkv"
      assert presence.media_dir == "/media/movies"
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

    test "updates media_dir if a path moves between watch roots" do
      _first = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies")
      moved = FilePresence.stamp("/media/movies/sample.mkv", "/media/extra")

      assert moved.media_dir == "/media/extra"
      assert Repo.aggregate(FilePresence, :count) == 1
    end

    test "records byte size when given (for relink-on-move matching)" do
      now = DateTime.utc_now()

      presence =
        FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", now, size: 123_456)

      assert presence.size == 123_456
    end

    test "a restamp without a size leaves an existing size intact" do
      # The bulk last_seen_at refresh restamps every file with no size; it
      # must not wipe the size a new-file detection recorded.
      _first =
        FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", DateTime.utc_now(), size: 999)

      refreshed = FilePresence.stamp("/media/movies/sample.mkv", "/media/movies")

      assert refreshed.size == 999
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

    test "records the size for new rows when given {path, size} entries" do
      FilePresence.stamp_many([{"/media/movies/sized.mkv", 4_000}], "/media/movies")

      [presence] = Repo.all(FilePresence)
      assert presence.size == 4_000
    end

    test "fills a missing size on restamp (backfill for pre-feature rows)" do
      FilePresence.stamp("/media/movies/legacy.mkv", "/media/movies")

      FilePresence.stamp_many([{"/media/movies/legacy.mkv", 7_500}], "/media/movies")

      [presence] = Repo.all(FilePresence)
      assert presence.size == 7_500
      assert FilePresence.total_size_bytes() == 7_500
    end

    test "never overwrites a recorded size on restamp" do
      FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", DateTime.utc_now(), size: 999)

      FilePresence.stamp_many([{"/media/movies/sample.mkv", 123}], "/media/movies")

      [presence] = Repo.all(FilePresence)
      assert presence.size == 999
    end

    test "plain path entries leave an existing size intact" do
      FilePresence.stamp("/media/movies/sample.mkv", "/media/movies", DateTime.utc_now(), size: 999)

      FilePresence.stamp_many(["/media/movies/sample.mkv"], "/media/movies")

      [presence] = Repo.all(FilePresence)
      assert presence.size == 999
    end
  end

  describe "list_paths_for_media_dir/1" do
    test "returns only paths in the given media directory" do
      FilePresence.stamp("/media/movies/a.mkv", "/media/movies")
      FilePresence.stamp("/media/movies/b.mkv", "/media/movies")
      FilePresence.stamp("/media/tv/series/c.mkv", "/media/tv")

      paths = FilePresence.list_paths_for_media_dir("/media/movies")

      assert MapSet.size(paths) == 2
      assert MapSet.member?(paths, "/media/movies/a.mkv")
      assert MapSet.member?(paths, "/media/movies/b.mkv")
      refute MapSet.member?(paths, "/media/tv/series/c.mkv")
    end

    test "returns empty set when no paths tracked" do
      assert MapSet.size(FilePresence.list_paths_for_media_dir("/nope")) == 0
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
