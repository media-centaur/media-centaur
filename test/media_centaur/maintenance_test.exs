defmodule MediaCentaur.MaintenanceTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.{FilePresence, PlayableItem}

  alias MediaCentaur.Library
  alias MediaCentaur.Maintenance
  alias MediaCentaur.Repo
  alias MediaCentaur.Review

  import MediaCentaur.TestFactory

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Review.list_pending_files()

      Maintenance.clear_database()

      assert [] = Review.list_pending_files()
    end

    test "destroys PlayableItem rows (Library Schema v2 Phase 2 leaf)" do
      # PlayableItem was introduced in Phase 2 as the canonical leaf.
      # `resources_in_delete_order/0` must include it — otherwise
      # `clear_database/0` leaves orphan PlayableItems referencing
      # containers that have been deleted.
      movie = create_standalone_movie(%{name: "Doomed Movie"})
      create_playable_item_for_movie(movie)

      assert Repo.aggregate(PlayableItem, :count) == 1

      Maintenance.clear_database()

      assert Repo.aggregate(PlayableItem, :count) == 0
    end

    test "destroys FilePresence rows so a post-clear scan re-detects files on disk" do
      # FilePresence is the scan's skip-ledger: the watcher startup scan
      # skips any path already in `FilePresence.list_paths_for_media_dir/1`
      # (watcher.ex). `clear_database/0` deletes the child WatchedFile rows
      # but the presence reference is a plain column (no DB cascade), so the
      # FilePresence parent rows survived — leaving a poisoned ledger that
      # made the post-clear watcher restart skip every file still on disk.
      # That is the "I cleared everything and it still won't pick up my
      # media" report: clearing must wipe the ledger so a rescan rebuilds
      # the library from disk.
      movie = create_standalone_movie(%{name: "Moved Movie"})

      file =
        create_linked_file(%{
          movie_id: movie.id,
          media_dir: "/media/test",
          file_path: "/media/test/sample.mkv"
        })

      assert file.file_path in FilePresence.list_paths_for_media_dir("/media/test")

      Maintenance.clear_database()

      assert Enum.empty?(FilePresence.list_paths_for_media_dir("/media/test"))
      assert Repo.aggregate(FilePresence, :count) == 0
    end
  end

  describe "rederive_extra_names/0" do
    test "heals a blank extra name and clears the blank count" do
      movie = create_movie(%{name: "Sample Movie"})

      blank =
        create_extra(%{
          movie_id: movie.id,
          name: nil,
          content_url: "/media/test/Sample Show - Season 01/Extras/Making Of.mkv"
        })

      assert Maintenance.blank_extra_names_count() == 1

      assert {:ok, %{scanned: 1, updated: 1, skipped: 0}} = Maintenance.rederive_extra_names()

      assert Repo.get!(Library.Extra, blank.id).name == "Making Of"
      assert Maintenance.blank_extra_names_count() == 0
    end
  end
end
