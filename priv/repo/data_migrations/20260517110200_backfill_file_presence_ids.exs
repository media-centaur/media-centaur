defmodule MediaCentarr.Repo.DataMigrations.BackfillFilePresenceIds do
  @moduledoc """
  Backfills `file_presence_id` on every `library_watched_files` and
  `library_extra_files` row by ensuring a matching `library_file_presences`
  row exists for the file's `(file_path, watch_dir)` and stamping its id
  onto the leaf row.

  Runs between the Phase-3 schema migration (which adds the nullable FK
  column) and the follow-up migration that tightens the column to
  `null: false`. Idempotent — re-running is a no-op once every row is
  linked.

  This file is **append-only**. Never edit a shipped data migration.

  Campaign: library-presence-unification, Phase 3. See ADR-045.
  """
  use Ecto.Migration

  @ensure_presence """
  INSERT INTO library_file_presences
    (id, file_path, watch_dir, last_seen_at, inserted_at, updated_at)
  VALUES (?, ?, ?, ?, ?, ?)
  ON CONFLICT(file_path) DO NOTHING
  """

  def up, do: backfill(repo())
  def down, do: :ok

  @doc """
  Backfill body, exposed for direct testing. Idempotent — `ON CONFLICT
  DO NOTHING` makes presence insertion safe on re-run, and the UPDATE
  is gated by `file_presence_id IS NULL`.
  """
  def backfill(repo) do
    cond do
      not table_exists?(repo, "library_file_presences") -> :ok
      not table_exists?(repo, "library_watched_files") -> :ok
      not column_exists?(repo, "library_watched_files", "file_presence_id") -> :ok
      true -> Enum.each(["library_watched_files", "library_extra_files"], &backfill_table(repo, &1))
    end
  end

  defp backfill_table(repo, table) do
    {:ok, %{rows: rows}} =
      repo.query("SELECT file_path, watch_dir FROM #{table} WHERE file_presence_id IS NULL")

    Enum.each(rows, fn [file_path, watch_dir] ->
      ensure_presence_and_link(repo, table, file_path, watch_dir)
    end)
  end

  defp ensure_presence_and_link(repo, table, file_path, watch_dir) do
    now_usec = DateTime.utc_now()
    now_seconds = DateTime.utc_now(:second)

    repo.query!(@ensure_presence, [
      Ecto.UUID.generate(),
      file_path,
      watch_dir || "",
      now_usec,
      now_seconds,
      now_seconds
    ])

    repo.query!(
      """
      UPDATE #{table}
      SET file_presence_id = (SELECT id FROM library_file_presences WHERE file_path = ?)
      WHERE file_path = ? AND file_presence_id IS NULL
      """,
      [file_path, file_path]
    )
  end

  defp table_exists?(repo, name) do
    case repo.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", [name]) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end

  defp column_exists?(repo, table, column) do
    {:ok, %{rows: rows}} = repo.query("PRAGMA table_info(#{table})")
    Enum.any?(rows, fn row -> Enum.at(row, 1) == column end)
  end
end
