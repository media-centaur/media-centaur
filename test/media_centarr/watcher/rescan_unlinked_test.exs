defmodule MediaCentarr.Watcher.RescanUnlinkedTest do
  @moduledoc """
  Regression test for the silent-drop bug: when a transient external
  failure (e.g. an invalid TMDB API key) caused Discovery to fail a
  file in the search stage, the message was dropped by Broadway with
  no retry path. Re-broadcasting only happened for genuinely *new*
  files, so stranded rows (present in `watcher_files`, no link in
  `library_watched_files`) sat forever after a restart.

  `Watcher.Supervisor.rescan_unlinked/0` walks `watcher_files` and
  re-emits `{:file_detected, ...}` for any present row that has no
  matching `library_watched_files` link, so the next pipeline pass
  (with the failure resolved) recovers the stranded file.

  Append-only per ADR-027.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.FilePresence
  alias MediaCentarr.Watcher.Supervisor, as: WatcherSupervisor

  setup do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.pipeline_input())
    :ok
  end

  describe "rescan_unlinked/0" do
    test "emits :file_detected for present rows with no library link" do
      stranded_path = "/tmp/test/stranded.mkv"
      linked_path = "/tmp/test/linked.mkv"
      watch_dir = "/tmp/test"

      FilePresence.record_file(stranded_path, watch_dir)
      FilePresence.record_file(linked_path, watch_dir)

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: linked_path, watch_dir: watch_dir, movie_id: movie.id})

      assert {:ok, 1} = WatcherSupervisor.rescan_unlinked()

      assert_receive {:file_detected, %{path: ^stranded_path, watch_dir: ^watch_dir}}, 500
      refute_receive {:file_detected, %{path: ^linked_path}}, 100
    end

    test "returns {:ok, 0} and emits no events when nothing is stranded" do
      linked_path = "/tmp/test/only_linked.mkv"
      watch_dir = "/tmp/test"

      FilePresence.record_file(linked_path, watch_dir)
      movie = create_movie(%{name: "Sample Movie B"})
      create_linked_file(%{file_path: linked_path, watch_dir: watch_dir, movie_id: movie.id})

      assert {:ok, 0} = WatcherSupervisor.rescan_unlinked()
      refute_receive {:file_detected, _}, 100
    end

    test "returns {:ok, 0} when watcher_files is empty" do
      assert {:ok, 0} = WatcherSupervisor.rescan_unlinked()
      refute_receive {:file_detected, _}, 100
    end

    test "ignores absent rows even if they have no library link" do
      absent_path = "/tmp/test/gone.mkv"
      watch_dir = "/tmp/test"

      FilePresence.record_file(absent_path, watch_dir)
      FilePresence.mark_files_absent([absent_path])

      assert {:ok, 0} = WatcherSupervisor.rescan_unlinked()
      refute_receive {:file_detected, _}, 100
    end

    test "emits one event per stranded row across multiple files" do
      paths = ["/tmp/test/a.mkv", "/tmp/test/b.mkv", "/tmp/test/c.mkv"]
      watch_dir = "/tmp/test"

      Enum.each(paths, &FilePresence.record_file(&1, watch_dir))

      assert {:ok, 3} = WatcherSupervisor.rescan_unlinked()

      Enum.each(paths, fn path ->
        assert_receive {:file_detected, %{path: ^path, watch_dir: ^watch_dir}}, 500
      end)
    end
  end
end
