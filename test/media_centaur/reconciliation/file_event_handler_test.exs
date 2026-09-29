defmodule MediaCentaur.Reconciliation.FileEventHandlerTest do
  @moduledoc """
  The episode-mapping queue's side of "this file is no longer library
  content": a file deleted from disk or retracted by an ignore rule
  (`{:files_removed, paths}` on `Topics.library_file_events()`) has no
  position left to decide. Until 2026-09-29 only the Review queue reacted,
  and a removed file stayed listed at a path that no longer existed.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Reconciliation.FileEventHandler
  alias MediaCentaur.Topics

  defp divert!(file_path) do
    {:ok, awaiting} =
      Reconciliation.divert(%{
        file_path: file_path,
        media_dir: "/media/test",
        tmdb_id: 4242,
        claimed_season: 2,
        claimed_episode: 1
      })

    awaiting
  end

  describe "drop_awaiting_files/1" do
    test "deletes the rows for the given paths, whatever their status, and leaves the rest" do
      gone = divert!("/media/test/gone.mkv")
      {:ok, _} = Reconciliation.dismiss_awaiting(divert!("/media/test/dismissed.mkv"))
      kept = divert!("/media/test/stays.mkv")

      assert {:ok, 2} =
               Reconciliation.drop_awaiting_files(["/media/test/gone.mkv", "/media/test/dismissed.mkv"])

      ids = Enum.map(Reconciliation.list_awaiting(), & &1.id)
      refute gone.id in ids
      assert ids == [kept.id]
    end

    test "reports zero for an empty path list" do
      assert {:ok, 0} = Reconciliation.drop_awaiting_files([])
    end
  end

  describe "reacting to {:files_removed, paths}" do
    setup do
      start_supervised!(FileEventHandler)
      :ok
    end

    test "drops the row for a removed file" do
      divert!("/media/test/gone.mkv")
      kept = divert!("/media/test/stays.mkv")

      Topics.publish(Topics.library_file_events(), {:files_removed, ["/media/test/gone.mkv"]})
      :ok = FileEventHandler.__sync_for_test__()

      assert Enum.map(Reconciliation.list_awaiting(), & &1.id) == [kept.id]
    end
  end
end
