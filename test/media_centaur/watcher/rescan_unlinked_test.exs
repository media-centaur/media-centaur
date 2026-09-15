defmodule MediaCentaur.Watcher.RescanUnlinkedTest do
  @moduledoc """
  Regression test for the silent-drop bug: when a transient external
  failure (e.g. an invalid TMDB API key) caused Discovery to fail a
  file in the search stage, the message was dropped by Broadway with
  no retry path. Re-broadcasting only happened for genuinely *new*
  files, so stranded rows (FilePresence with no link in
  `library_watched_files`) sat forever after a restart.

  Post-Phase-7 of the library-presence-unification campaign,
  `Watcher.Rescan.rescan_unlinked/0` walks `library_file_presences`
  (the watcher_files table is gone) and re-emits
  `{:file_detected, ...}` for any presence row that has no matching
  `library_watched_files` link *and still exists on disk*, so the next
  pipeline pass (with the failure resolved) recovers the stranded file.

  The on-disk check (added after a real incident where a large backlog
  of presence rows for since-deleted titles got resurrected the moment
  the startup race that had been silently skipping this function for a
  long time was fixed) matters because "stranded" is not the only way a
  presence row can outlive its `WatchedFile` link — a title the user
  removed and deleted from disk leaves the exact same shape (presence
  row, no link) with no file to recover.

  Two further classes of row must never be re-emitted. One is a file
  linked as an `ExtraFile` — a bonus feature — which
  `Library.Files.linked_paths_subquery/0` used to miss because it read
  `library_watched_files` alone, making every imported extra look
  stranded on every boot.

  The other is a row under an ignore rule. `exclude_dirs` (a path rule) and `skip_dirs` (a name rule) only
  ever filtered the directory *walk*, so presence rows recorded before
  a rule was added kept being re-emitted on every boot — each one
  costing a parse and two TMDB searches that could not resolve. See
  `docs/plans/2026-09-15-ignore-rules-unification.md`.

  Append-only per ADR-027.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.Rescan

  setup do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_input())

    tmp_dir = Path.join(System.tmp_dir!(), "rescan_unlinked_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{media_dir: tmp_dir}
  end

  # A stranded presence row whose file genuinely still exists on disk —
  # the transient-failure scenario this module guards against.
  defp write_stranded_file!(media_dir, name) do
    path = Path.join(media_dir, name)
    File.write!(path, "stranded")
    FilePresence.stamp(path, media_dir)
    path
  end

  describe "rescan_unlinked/0" do
    test "emits :file_detected for presence rows with no library link", %{media_dir: media_dir} do
      stranded_path = write_stranded_file!(media_dir, "stranded.mkv")
      linked_path = Path.join(media_dir, "linked.mkv")
      # `linked_path` will get its presence stamped via `create_linked_file`
      # → `Library.Files.link/1` → auto-stamp; no need for a separate stamp.

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: linked_path, media_dir: media_dir, movie_id: movie.id})

      assert {:ok, 1} = Rescan.rescan_unlinked()

      assert_receive {:file_detected, %{path: ^stranded_path, media_dir: ^media_dir}}, 500
      refute_receive {:file_detected, %{path: ^linked_path}}, 100
    end

    test "returns {:ok, 0} and emits no events when nothing is stranded", %{media_dir: media_dir} do
      linked_path = Path.join(media_dir, "only_linked.mkv")

      movie = create_movie(%{name: "Sample Movie B"})
      create_linked_file(%{file_path: linked_path, media_dir: media_dir, movie_id: movie.id})

      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, _}, 100
    end

    test "returns {:ok, 0} when library_file_presences is empty" do
      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, _}, 100
    end

    test "emits one event per stranded row across multiple files", %{media_dir: media_dir} do
      paths = for n <- ["a", "b", "c"], do: write_stranded_file!(media_dir, "#{n}.mkv")

      assert {:ok, 3} = Rescan.rescan_unlinked()

      Enum.each(paths, fn path ->
        assert_receive {:file_detected, %{path: ^path, media_dir: ^media_dir}}, 500
      end)
    end

    test "does not re-emit a presence row whose file no longer exists on disk", %{
      media_dir: media_dir
    } do
      # Same shape as a real stranded row (presence, no WatchedFile link) but
      # nothing at that path — a title removed and deleted from disk, not a
      # transient pipeline failure. Re-emitting would resurrect deleted
      # content (the incident this test guards against).
      gone_path = Path.join(media_dir, "deleted.mkv")
      FilePresence.stamp(gone_path, media_dir)

      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, %{path: ^gone_path}}, 100
    end

    test "still recovers a genuinely stranded file alongside a deleted one", %{
      media_dir: media_dir
    } do
      stranded_path = write_stranded_file!(media_dir, "stranded.mkv")
      gone_path = Path.join(media_dir, "deleted.mkv")
      FilePresence.stamp(gone_path, media_dir)

      assert {:ok, 1} = Rescan.rescan_unlinked()

      assert_receive {:file_detected, %{path: ^stranded_path, media_dir: ^media_dir}}, 500
      refute_receive {:file_detected, %{path: ^gone_path}}, 100
    end

    test "does not re-emit a presence row under a path rule", %{media_dir: media_dir} do
      captures_dir = Path.join(media_dir, "Captures")
      File.mkdir_p!(captures_dir)
      ignored_path = write_stranded_file!(captures_dir, "Sample Capture 2025-06-29 13-19-52.mkv")

      :ok = Config.update(:exclude_dirs, [captures_dir])

      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, %{path: ^ignored_path}}, 100
    end

    test "does not re-emit a presence row under a name rule", %{media_dir: media_dir} do
      sample_dir = Path.join(media_dir, "Sample")
      File.mkdir_p!(sample_dir)
      ignored_path = write_stranded_file!(sample_dir, "padding.mkv")

      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, %{path: ^ignored_path}}, 100
    end

    test "does not re-emit a presence row for a file that is not a recognised video", %{
      media_dir: media_dir
    } do
      ignored_path = write_stranded_file!(media_dir, "cover.jpg")

      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, %{path: ^ignored_path}}, 100
    end

    test "does not re-emit a file linked as an extra", %{media_dir: media_dir} do
      # Bonus features are linked through `library_extra_files`, not
      # `library_watched_files`. Treating them as stranded re-fed every
      # imported extra to the pipeline on each boot.
      extra_path = Path.join(media_dir, "behind the scenes.mkv")
      File.write!(extra_path, "extra")

      movie = create_movie(%{name: "Sample Movie C"})

      extra =
        create_extra(%{
          movie_id: movie.id,
          name: "Behind the Scenes",
          kind: :featurette,
          content_url: extra_path
        })

      create_extra_file_for_extra(extra, %{media_dir: media_dir})

      assert {:ok, 0} = Rescan.rescan_unlinked()
      refute_receive {:file_detected, %{path: ^extra_path}}, 100
    end

    test "still recovers a stranded file alongside one under a path rule", %{
      media_dir: media_dir
    } do
      captures_dir = Path.join(media_dir, "Captures")
      File.mkdir_p!(captures_dir)
      ignored_path = write_stranded_file!(captures_dir, "Sample Capture 2025-06-29 13-19-52.mkv")
      stranded_path = write_stranded_file!(media_dir, "stranded.mkv")

      :ok = Config.update(:exclude_dirs, [captures_dir])

      assert {:ok, 1} = Rescan.rescan_unlinked()

      assert_receive {:file_detected, %{path: ^stranded_path, media_dir: ^media_dir}}, 500
      refute_receive {:file_detected, %{path: ^ignored_path}}, 100
    end
  end
end
