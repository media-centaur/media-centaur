defmodule MediaCentarr.Watcher.RecordSeenTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.{FilePresence, WatchedFile}
  alias MediaCentarr.Watcher

  describe "record_seen/1" do
    test "writes both library_watched_files and library_file_presences" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      playable_item = create_playable_item_for_movie(movie)

      attrs = %{
        file_path: "/media/movies/sample.mkv",
        watch_dir: "/media/movies",
        playable_item_id: playable_item.id
      }

      assert {:ok, %WatchedFile{} = file} = Watcher.record_seen(attrs)
      assert file.playable_item_id == playable_item.id
      assert file.file_path == "/media/movies/sample.mkv"

      presence = Repo.get_by!(FilePresence, file_path: "/media/movies/sample.mkv")
      assert presence.watch_dir == "/media/movies"
      assert file.file_presence_id == presence.id
    end

    test "is idempotent — repeated calls do not duplicate rows" do
      movie = create_entity(%{type: :movie, name: "Sample Movie"})
      playable_item = create_playable_item_for_movie(movie)

      attrs = %{
        file_path: "/media/movies/sample.mkv",
        watch_dir: "/media/movies",
        playable_item_id: playable_item.id
      }

      assert {:ok, _} = Watcher.record_seen(attrs)
      assert {:ok, _} = Watcher.record_seen(attrs)
      assert {:ok, _} = Watcher.record_seen(attrs)

      assert length(Library.list_watched_files()) == 1
      assert Repo.aggregate(FilePresence, :count) == 1
    end

    test "returns {:error, _} when link_file fails (empty file_path)" do
      # Force a validation failure: empty file_path triggers the
      # validate_required check on WatchedFile.link_file_changeset/1.
      attrs = %{
        file_path: "",
        watch_dir: "/media/movies"
      }

      assert {:error, _} = Watcher.record_seen(attrs)

      assert Library.list_watched_files() == []
      assert Repo.aggregate(FilePresence, :count) == 0
    end
  end
end
