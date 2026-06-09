defmodule MediaCentaur.Repo.Migrations.CreatePursuitUnits do
  @moduledoc """
  Composite pursuits, step 1 of 2 (ADR-055): create
  `acquisition_pursuit_units` (one wanted thing per row, carrying the
  attempt thread) and `acquisition_target_units` (which units a
  target's release covers), then backfill — every existing pursuit
  becomes a single-unit composite whose unit copies the pursuit's
  thread fields verbatim, and every existing target covers its
  pursuit's sole unit.

  The thread columns stay on `acquisition_pursuits` until step 2
  (`drop_pursuit_thread_columns`) so each step is independently
  green. Backfills are idempotent (`WHERE NOT EXISTS` guards).
  """
  use Ecto.Migration

  # Standard SQLite UUIDv4 generator — evaluated per row in INSERT…SELECT
  # because randomblob/1 is non-deterministic.
  @uuid_sql """
  lower(hex(randomblob(4))) || '-' ||
  lower(hex(randomblob(2))) || '-4' ||
  substr(lower(hex(randomblob(2))), 2) || '-' ||
  substr('89ab', (abs(random()) % 4) + 1, 1) ||
  substr(lower(hex(randomblob(2))), 2) || '-' ||
  lower(hex(randomblob(6)))
  """

  def up do
    create table(:acquisition_pursuit_units, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :pursuit_id,
          references(:acquisition_pursuits, type: :binary_id, on_delete: :delete_all),
          null: false

      add :state, :string, null: false, default: "active"
      add :position, :integer, null: false, default: 0
      add :label, :string
      add :query, :string
      add :current_target_id, :binary_id
      add :tried_release_guids, {:array, :string}, null: false, default: []
      add :attempt_count, :integer, null: false, default: 0
      add :awaiting_decision_at, :utc_datetime
      add :stall_first_seen_at, :utc_datetime
      add :zero_seeders_first_seen_at, :utc_datetime
      add :last_queue_state, :string
      add :last_queue_health, :string

      timestamps(type: :utc_datetime)
    end

    create index(:acquisition_pursuit_units, [:pursuit_id])
    create index(:acquisition_pursuit_units, [:state])

    create table(:acquisition_target_units, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :target_id,
          references(:acquisition_targets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :unit_id,
          references(:acquisition_pursuit_units, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:acquisition_target_units, [:target_id, :unit_id])
    create index(:acquisition_target_units, [:unit_id])

    # One unit per existing pursuit, thread fields copied verbatim. Unit
    # state mirrors the pursuit state 1:1 — "partial" doesn't exist yet,
    # so the pre-composite states map onto the unit state machine exactly.
    # `query` seeds from `manual_query` so query-door units keep their
    # concrete search string.
    execute("""
    INSERT INTO acquisition_pursuit_units
      (id, pursuit_id, state, position, label, query, current_target_id,
       tried_release_guids, attempt_count, awaiting_decision_at,
       stall_first_seen_at, zero_seeders_first_seen_at,
       last_queue_state, last_queue_health, inserted_at, updated_at)
    SELECT
      #{@uuid_sql},
      p.id, p.state, 0, NULL, p.manual_query, p.current_target_id,
      p.tried_release_guids, p.attempt_count, p.awaiting_decision_at,
      p.stall_first_seen_at, p.zero_seeders_first_seen_at,
      p.last_queue_state, p.last_queue_health, p.inserted_at, p.updated_at
    FROM acquisition_pursuits p
    WHERE NOT EXISTS (
      SELECT 1 FROM acquisition_pursuit_units u WHERE u.pursuit_id = p.id
    )
    """)

    # Every existing target covers its pursuit's sole unit. Targets with a
    # nilified pursuit_id (pursuit deleted) get no coverage row.
    execute("""
    INSERT INTO acquisition_target_units (id, target_id, unit_id, inserted_at, updated_at)
    SELECT #{@uuid_sql}, t.id, u.id, t.inserted_at, t.updated_at
    FROM acquisition_targets t
    JOIN acquisition_pursuit_units u ON u.pursuit_id = t.pursuit_id
    WHERE NOT EXISTS (
      SELECT 1 FROM acquisition_target_units tu WHERE tu.target_id = t.id
    )
    """)
  end

  def down do
    drop table(:acquisition_target_units)
    drop table(:acquisition_pursuit_units)
  end
end
