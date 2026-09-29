defmodule MediaCentaur.Repo.DataMigrations.AwaitingFilesDropResolvedTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.EpisodeMapping
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.AwaitingFilesDropResolved

  defp divert!(file_path) do
    {:ok, file} =
      EpisodeMapping.divert(%{file_path: file_path, media_dir: "/media", tmdb_id: 42, claimed_season: 2})

    file
  end

  # The schema no longer admits the retired status, so the legacy state is
  # written the way the old app left it: straight into the column.
  defp make_resolved!(file) do
    Repo.query!("UPDATE episode_mapping_awaiting_files SET status = 'resolved' WHERE id = ?", [
      file.id
    ])
  end

  defp statuses do
    %{rows: rows} = Repo.query!("SELECT status FROM episode_mapping_awaiting_files ORDER BY status", [])
    List.flatten(rows)
  end

  describe "sweep/1" do
    test "deletes resolved rows and leaves pending and dismissed ones" do
      make_resolved!(divert!("/media/resolved.mkv"))
      divert!("/media/pending.mkv")
      {:ok, _} = EpisodeMapping.dismiss_awaiting(divert!("/media/dismissed.mkv"))

      assert :ok = AwaitingFilesDropResolved.sweep(Repo)

      assert statuses() == ["dismissed", "pending"]
    end

    test "is idempotent" do
      make_resolved!(divert!("/media/resolved.mkv"))

      assert :ok = AwaitingFilesDropResolved.sweep(Repo)
      assert :ok = AwaitingFilesDropResolved.sweep(Repo)
      assert statuses() == []
    end
  end
end
