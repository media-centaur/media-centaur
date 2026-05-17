defmodule MediaCentarr.Repo.DataMigrations.BackfillFilePresenceIdsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.{FilePresence, WatchedFile}
  alias MediaCentarr.Repo
  alias MediaCentarr.Repo.DataMigrations.BackfillFilePresenceIds

  describe "backfill/1" do
    test "creates a FilePresence row and links it from a pre-migration WatchedFile" do
      movie = create_entity(%{type: :movie, name: "Backfill Movie"})
      item = create_playable_item_for_movie(movie)

      insert_orphan_watched_file(item.id, "/media/test/bf.mkv", "/media/test")

      assert :ok = BackfillFilePresenceIds.backfill(Repo)

      presence = Repo.get_by!(FilePresence, file_path: "/media/test/bf.mkv")
      assert presence.watch_dir == "/media/test"

      file = Repo.get_by!(WatchedFile, file_path: "/media/test/bf.mkv")
      assert file.file_presence_id == presence.id
    end

    test "is idempotent — second run leaves the row count unchanged" do
      movie = create_entity(%{type: :movie, name: "Idempotent Movie"})
      item = create_playable_item_for_movie(movie)
      _ = create_linked_file(%{playable_item_id: item.id, file_path: "/media/test/idem.mkv"})

      assert :ok = BackfillFilePresenceIds.backfill(Repo)
      assert :ok = BackfillFilePresenceIds.backfill(Repo)

      assert Repo.aggregate(FilePresence, :count) == 1
    end

    test "no-op when there are no pre-migration rows to backfill" do
      assert :ok = BackfillFilePresenceIds.backfill(Repo)
      assert Repo.aggregate(FilePresence, :count) == 0
    end
  end

  # Raw INSERT that bypasses the changeset so we can simulate
  # pre-Phase-3 state where file_presence_id is NULL. The runtime
  # changeset's `validate_required(:file_presence_id)` would otherwise
  # block this shape.
  defp insert_orphan_watched_file(playable_item_id, file_path, watch_dir) do
    now = DateTime.utc_now(:second)

    Repo.query!(
      """
      INSERT INTO library_watched_files
        (id, file_path, watch_dir, playable_item_id, file_presence_id,
         inserted_at, updated_at)
      VALUES (?, ?, ?, ?, NULL, ?, ?)
      """,
      [Ecto.UUID.generate(), file_path, watch_dir, playable_item_id, now, now]
    )
  end
end
