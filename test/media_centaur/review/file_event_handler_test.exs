defmodule MediaCentaur.Review.FileEventHandlerTest do
  @moduledoc """
  The review queue's side of "this file is no longer library content".

  Two ways a queued file stops being reviewable, and until 2026-09-15
  neither removed its row: the file was deleted from disk (the row sat
  there pointing at nothing), or an ignore rule was added over its
  directory (`Watcher.Rescan.retract_ignored/0` broadcasts the same
  removal). Both arrive as `{:files_removed, paths}` on
  `Topics.library_file_events()`, which `Library.FileEventHandler`
  already consumes for the library's own bookkeeping.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits
  import MediaCentaur.TestFactory

  alias MediaCentaur.Review
  alias MediaCentaur.Review.Events.FileReviewed
  alias MediaCentaur.Review.FileEventHandler
  alias MediaCentaur.Topics

  describe "drop_pending_files/1" do
    test "deletes the queue rows for the given paths and leaves the rest" do
      dropped = create_pending_file(%{file_path: "/media/test/gone.mkv"})
      kept = create_pending_file(%{file_path: "/media/test/stays.mkv"})

      assert {:ok, 1} = Review.drop_pending_files(["/media/test/gone.mkv"])

      ids = Enum.map(Review.list_pending_files(), & &1.id)
      refute dropped.id in ids
      assert kept.id in ids
    end

    test "reports zero and touches nothing when no path is queued" do
      kept = create_pending_file(%{file_path: "/media/test/stays.mkv"})

      assert {:ok, 0} = Review.drop_pending_files(["/media/test/never-queued.mkv"])
      assert Enum.map(Review.list_pending_files(), & &1.id) == [kept.id]
    end

    test "reports zero for an empty path list" do
      assert {:ok, 0} = Review.drop_pending_files([])
    end

    test "tells review subscribers the file left the queue" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.review_updates())
      dropped = create_pending_file(%{file_path: "/media/test/gone.mkv"})
      dropped_id = dropped.id

      assert {:ok, 1} = Review.drop_pending_files(["/media/test/gone.mkv"])

      assert_receive {:file_reviewed, %FileReviewed{pending_file_id: ^dropped_id}}, 500
    end

    test "drops a row whatever its status — a dismissed row is queue state too" do
      dismissed = create_pending_file(%{file_path: "/media/test/dismissed.mkv"})
      {:ok, _} = Review.dismiss_pending_file(dismissed)

      assert {:ok, 1} = Review.drop_pending_files(["/media/test/dismissed.mkv"])
      assert Review.list_pending_files() == []
    end
  end

  describe "reacting to {:files_removed, paths}" do
    setup do
      start_supervised!(FileEventHandler)
      :ok
    end

    test "drops the queue row for a removed file" do
      dropped = create_pending_file(%{file_path: "/media/test/gone.mkv"})
      kept = create_pending_file(%{file_path: "/media/test/stays.mkv"})

      Topics.publish(Topics.library_file_events(), {:files_removed, ["/media/test/gone.mkv"]})
      :ok = FileEventHandler.__sync_for_test__()
      await_supervised_tasks()

      ids = Enum.map(Review.list_pending_files(), & &1.id)
      refute dropped.id in ids
      assert kept.id in ids
    end

    test "ignores an unrelated message on the topic" do
      kept = create_pending_file(%{file_path: "/media/test/stays.mkv"})

      Topics.publish(Topics.library_file_events(), {:something_else, ["/media/test/stays.mkv"]})
      :ok = FileEventHandler.__sync_for_test__()

      assert Enum.map(Review.list_pending_files(), & &1.id) == [kept.id]
    end
  end
end
