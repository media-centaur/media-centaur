defmodule MediaCentaur.Repo.Migrations.WatchProgressPerProfile do
  @moduledoc """
  Watch progress belongs to a profile (ADR-078, phase 2). Every existing
  row is the oldest profile's — the owner profile the phase 1 migration
  created — and the unique key becomes `(profile_id, playable_item_id)`.

  SQLite cannot add a NOT NULL column to a filled table, so the table is
  rebuilt; the copy fills `profile_id` in the same statement, which is
  why no UPDATE (and no MC0015 carve-out) is needed. The FK to `profiles`
  cascades: removing a profile removes its rows, no job involved. The
  composite index leads with `profile_id`, so `playable_item_id` keeps
  its own index for the cascade from `library_playable_items`, as every
  FK child column here has (`20260405173122_add_library_fk_indexes`).

  Between `migrate` and the restart the outgoing release can still write
  a row without a profile; `NOT NULL` refuses it, the progress worker
  logs the failed flush and retries on its next tick, and the new release
  is serving by then. Not reversible: rows of several profiles would
  collapse onto one key.
  """
  use Ecto.Migration

  def up do
    create table(:library_watch_progress_next, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :position_seconds, :float, default: 0.0
      add :duration_seconds, :float, default: 0.0
      add :completed, :boolean, default: false
      add :last_watched_at, :utc_datetime

      add :playable_item_id,
          references(:library_playable_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    execute """
    INSERT INTO library_watch_progress_next
      (id, position_seconds, duration_seconds, completed, last_watched_at,
       playable_item_id, profile_id, inserted_at, updated_at)
    SELECT id, position_seconds, duration_seconds, completed, last_watched_at,
           playable_item_id,
           (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1),
           inserted_at, updated_at
    FROM library_watch_progress
    """

    drop table(:library_watch_progress)
    rename table(:library_watch_progress_next), to: table(:library_watch_progress)

    create unique_index(:library_watch_progress, [:profile_id, :playable_item_id])
    create index(:library_watch_progress, [:playable_item_id])

    create index(:library_watch_progress, [:completed, :last_watched_at],
             name: :library_watch_progress_completed_last_watched_at_index
           )
  end

  def down do
    raise Ecto.MigrationError,
          "watch_progress_per_profile is not reversible — rows of several profiles would collapse onto one playable_item_id"
  end
end
