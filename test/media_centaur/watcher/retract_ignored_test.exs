defmodule MediaCentaur.Watcher.RetractIgnoredTest do
  @moduledoc """
  Adding an ignore rule used to filter only future work: the directory
  stopped being walked, but everything already recorded under it stayed
  in the database — presence rows that the recovery re-emit kept feeding
  back to the pipeline, and review-queue rows for files the user had
  said were not library content.

  An ignore rule states that a subtree *is not* library content, so
  recorded state must not claim otherwise. `retract_ignored/0` is that
  reconciliation.

  The exception is content already imported from the subtree. That state
  is forbidden by the invariant in `Watcher.IgnoreRules` (Settings
  rejects such a rule), so a row that shows it can only pre-date the
  guard — it is reported, never destroyed. Silently retracting it would
  delete a user's library entry for a file still sitting on disk.
  """
  use MediaCentaur.DataCase, async: false

  import ExUnit.CaptureLog
  import MediaCentaur.TaskAwaits
  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Review
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.ConfigListener
  alias MediaCentaur.Watcher.Rescan

  setup do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_file_events())

    media_dir = Path.join(System.tmp_dir!(), "retract_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(media_dir)
    on_exit(fn -> File.rm_rf!(media_dir) end)

    %{media_dir: media_dir}
  end

  # Saving a rule triggers its own retraction (via ConfigListener), so a
  # test that then calls `retract_ignored/0` explicitly must let the
  # triggered pass finish first — otherwise the two race for the same rows.
  defp put_rules!(key, value) do
    :ok = Config.update(key, value)
    settle_retraction()
  end

  defp settle_retraction do
    ConfigListener.__sync_for_test__()
    await_supervised_tasks()
    MediaCentaur.Library.FileEventHandler.__sync_for_test__()
    await_supervised_tasks()
  end

  defp stamp_file!(dir, name) do
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, "content")
    FilePresence.stamp(path, Path.dirname(dir))
    path
  end

  describe "retract_ignored/0" do
    test "retracts an unlinked presence row under a path rule", %{media_dir: media_dir} do
      captures = Path.join(media_dir, "Captures")
      put_rules!(:exclude_dirs, [captures])
      ignored_path = stamp_file!(captures, "clip.mkv")

      assert {:ok, 1} = Rescan.retract_ignored()

      assert_receive {:files_removed, [^ignored_path]}, 500
    end

    test "retracts an unlinked presence row under a name rule", %{media_dir: media_dir} do
      ignored_path = stamp_file!(Path.join(media_dir, "Sample"), "padding.mkv")

      assert {:ok, 1} = Rescan.retract_ignored()

      assert_receive {:files_removed, [^ignored_path]}, 500
    end

    test "clears the presence row, so the recovery re-emit has nothing to find", %{
      media_dir: media_dir
    } do
      captures = Path.join(media_dir, "Captures")
      put_rules!(:exclude_dirs, [captures])
      ignored_path = stamp_file!(captures, "clip.mkv")

      assert {:ok, 1} = Rescan.retract_ignored()
      :ok = MediaCentaur.Library.FileEventHandler.__sync_for_test__()
      await_supervised_tasks()

      refute ignored_path in FilePresence.list_paths_for_media_dir(media_dir)
    end

    test "leaves a presence row that no rule covers", %{media_dir: media_dir} do
      kept_path = stamp_file!(Path.join(media_dir, "Movies"), "Sample.Movie.mkv")

      assert {:ok, 0} = Rescan.retract_ignored()

      refute_receive {:files_removed, _}, 100
      assert kept_path in FilePresence.list_paths_for_media_dir(media_dir)
    end

    test "returns zero when there are no presence rows at all" do
      assert {:ok, 0} = Rescan.retract_ignored()
      refute_receive {:files_removed, _}, 100
    end

    test "never retracts an imported file, and reports the rule that covers it", %{
      media_dir: media_dir
    } do
      # Forbidden by the invariant, so reachable only for a rule added
      # before Settings enforced it. Destroying the library entry for a
      # file still on disk is the outcome this guards against.
      captures = Path.join(media_dir, "Captures")
      put_rules!(:exclude_dirs, [captures])

      File.mkdir_p!(captures)
      linked_path = Path.join(captures, "imported.mkv")
      File.write!(linked_path, "content")

      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{file_path: linked_path, media_dir: media_dir, movie_id: movie.id})

      log = capture_log(fn -> assert {:ok, 0} = Rescan.retract_ignored() end)

      assert log =~ "imported.mkv"
      refute_receive {:files_removed, _}, 100
      assert linked_path in FilePresence.list_paths_for_media_dir(media_dir)
    end

    test "drops the review-queue row for a retracted path", %{media_dir: media_dir} do
      captures = Path.join(media_dir, "Captures")
      put_rules!(:exclude_dirs, [captures])
      ignored_path = stamp_file!(captures, "clip.mkv")

      start_supervised!(MediaCentaur.Review.FileEventHandler)
      queued = create_pending_file(%{file_path: ignored_path, media_directory: media_dir})

      assert {:ok, 1} = Rescan.retract_ignored()
      :ok = MediaCentaur.Review.FileEventHandler.__sync_for_test__()

      refute queued.id in Enum.map(Review.list_pending_files(), & &1.id)
    end
  end

  describe "adding a rule triggers retraction" do
    # The rule set is only half the fix: the other half is that saving a
    # rule reconciles what is already recorded under it, rather than
    # leaving rows the user can't see and can't clear.
    test "a new path rule retracts the presence rows it covers", %{media_dir: media_dir} do
      captures = Path.join(media_dir, "Captures")
      ignored_path = stamp_file!(captures, "clip.mkv")

      :ok = Config.update(:exclude_dirs, [captures])
      settle_retraction()

      refute ignored_path in FilePresence.list_paths_for_media_dir(media_dir)
    end

    test "a new name rule retracts the presence rows it covers", %{media_dir: media_dir} do
      ignored_path = stamp_file!(Path.join(media_dir, "Featurettes"), "making-of.mkv")

      :ok = Config.update(:skip_dirs, ["featurettes"])
      settle_retraction()

      refute ignored_path in FilePresence.list_paths_for_media_dir(media_dir)
    end

    test "an unrelated config change retracts nothing", %{media_dir: media_dir} do
      kept_path = stamp_file!(Path.join(media_dir, "Movies"), "Sample.Movie.mkv")

      :ok = Config.update(:auto_approve_threshold, 0.9)
      settle_retraction()

      assert kept_path in FilePresence.list_paths_for_media_dir(media_dir)
    end
  end

  describe "reconcile/0" do
    test "retracts what a rule covers and re-emits what is still stranded", %{
      media_dir: media_dir
    } do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.pipeline_input())

      captures = Path.join(media_dir, "Captures")
      put_rules!(:exclude_dirs, [captures])
      ignored_path = stamp_file!(captures, "clip.mkv")
      stranded_path = stamp_file!(Path.join(media_dir, "Movies"), "Sample.Movie.mkv")

      assert {:ok, %{retracted: 1, reemitted: 1}} = Rescan.reconcile()

      assert_receive {:file_detected, %{path: ^stranded_path}}, 500
      refute_receive {:file_detected, %{path: ^ignored_path}}, 100
    end
  end
end
