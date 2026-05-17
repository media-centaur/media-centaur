defmodule MediaCentarr.Repo.Migrations.DropFilePresenceFk do
  use Ecto.Migration

  # Closes out the library-presence-unification campaign (ADR-046):
  # drops the DB-level FK + cascade on `file_presence_id` for both
  # `library_watched_files` and `library_extra_files`. The column
  # stays — it's still a useful lookup key from a leaf row to its
  # presence row — but cascading deletes are now an application
  # concern, enforced by `Library.AbsenceSweeper.purge_expired/1`
  # calling `Library.FileEventHandler.cleanup_removed_files/1` before
  # `Library.FilePresence.delete_paths/1`.
  #
  # SQLite doesn't support `ALTER TABLE ... ALTER COLUMN` or
  # `ALTER TABLE ... DROP CONSTRAINT`, but it does support
  # individual `RENAME COLUMN` / `ADD COLUMN` / `DROP COLUMN`. The
  # five-step sequence below swaps the FK-bearing column for a plain
  # UUID column without rebuilding the whole table, preserving every
  # other index and the inbound FK from `subtitles_tracks` →
  # `library_watched_files.id` (which references the primary key,
  # not the column we're swapping).
  #
  # See ADR-046 for the full reasoning.

  def up do
    swap_column(:library_watched_files)
    swap_column(:library_extra_files)
  end

  def down do
    raise Ecto.MigrationError,
      message: """
      irreversible: re-adding the FK + cascade is non-trivial on SQLite
      (would require a full table rebuild) and we've deliberately moved
      cascading-delete responsibility to the application layer per ADR-046.
      """
  end

  defp swap_column(table) when is_atom(table) do
    execute("ALTER TABLE #{table} RENAME COLUMN file_presence_id TO file_presence_id_legacy")
    # RENAME COLUMN preserves the existing index, which now points at
    # `file_presence_id_legacy` under the original name. Drop it so the
    # new index below can take the same name on the new column.
    execute("DROP INDEX IF EXISTS #{table}_file_presence_id_index")
    execute("ALTER TABLE #{table} ADD COLUMN file_presence_id BLOB")

    # credo:disable-for-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
    execute("UPDATE #{table} SET file_presence_id = file_presence_id_legacy")

    flush()

    create index(table, [:file_presence_id])

    execute("ALTER TABLE #{table} DROP COLUMN file_presence_id_legacy")
  end
end
