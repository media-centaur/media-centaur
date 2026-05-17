defmodule MediaCentarr.Repo.Migrations.CreateFilePresences do
  use Ecto.Migration

  # Campaign: library-presence-unification, Phase 1.
  #
  # Introduces `library_file_presences` as the durable record of "we
  # have observed this file on disk and when". WatchedFile and
  # ExtraFile will FK to this in Phase 3; the existing `watcher_files`
  # table is untouched here and gets dropped in Phase 7 after the
  # read-side flip.
  #
  # Non-breaking: nothing reads or writes this table yet. Future
  # phases dual-write from the watcher, backfill from `watcher_files`,
  # and flip the Library read sites.
  #
  # See ADR-045 (decisions/architecture/2026-05-17-045-file-presence-ownership.md).

  def change do
    create table(:library_file_presences, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :file_path, :string, null: false
      add :watch_dir, :string, null: false
      add :last_seen_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:library_file_presences, [:file_path])

    # AbsenceSweeper (Phase 6) sweeps stale rows scoped to a given
    # watch_dir; the compound index keeps that scan cheap as the
    # table grows.
    create index(:library_file_presences, [:watch_dir, :last_seen_at])
  end
end
