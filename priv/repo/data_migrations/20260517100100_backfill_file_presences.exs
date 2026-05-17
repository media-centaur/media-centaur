defmodule MediaCentarr.Repo.DataMigrations.BackfillFilePresences do
  @moduledoc """
  Seeds the new `library_file_presences` table from the legacy
  `watcher_files` table, intentionally skipping orphan rows (those
  where `state = :present` but no matching `library_watched_files`
  exists). Skipped paths are re-detected by the watcher's next scan
  and re-flow through the pipeline.

  This file is **append-only**. Never edit a shipped data migration.

  Campaign: library-presence-unification, Phase 2. See ADR-045.
  """
  use Ecto.Migration

  @select_eligible """
  SELECT k.file_path, k.watch_dir, k.updated_at, k.inserted_at
  FROM watcher_files k
  INNER JOIN library_watched_files w ON w.file_path = k.file_path
  WHERE k.state = 'present'
  """

  @insert_presence """
  INSERT INTO library_file_presences
    (id, file_path, watch_dir, last_seen_at, inserted_at, updated_at)
  VALUES (?, ?, ?, ?, ?, ?)
  ON CONFLICT(file_path) DO NOTHING
  """

  def up, do: backfill(repo())

  def down, do: :ok

  @doc """
  Backfill body, exposed for direct testing. Idempotent — the
  `ON CONFLICT DO NOTHING` clause makes a re-run safe.
  """
  def backfill(repo) do
    cond do
      not table_exists?(repo, "watcher_files") ->
        :ok

      not table_exists?(repo, "library_file_presences") ->
        :ok

      true ->
        {:ok, %{rows: rows}} = repo.query(@select_eligible)
        Enum.each(rows, &insert_one(repo, &1))
    end
  end

  defp insert_one(repo, [file_path, watch_dir, updated_at, inserted_at]) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()
    seen_at = parse_datetime(updated_at) || parse_datetime(inserted_at) || now
    inserted = parse_datetime(inserted_at) || now

    repo.query!(@insert_presence, [
      id,
      file_path,
      watch_dir,
      seen_at,
      inserted,
      DateTime.utc_now(:second)
    ])
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> datetime
      _ -> parse_naive(timestamp)
    end
  end

  defp parse_naive(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end

  defp table_exists?(repo, name) do
    case repo.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", [name]) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end
end
