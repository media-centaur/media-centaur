defmodule MediaCentaur.Repo.Migrations.DropPursuitThreadColumns do
  @moduledoc """
  Composite pursuits, step 2 of 2 (ADR-055): drop the attempt-thread
  columns from `acquisition_pursuits` — they now live on
  `acquisition_pursuit_units`, backfilled by step 1
  (`create_pursuit_units`).

  Down recreates the columns and restores each pursuit's thread from
  its first unit — lossless while every pursuit is single-unit.
  """
  use Ecto.Migration

  @thread_columns ~w(
    tried_release_guids attempt_count current_target_id awaiting_decision_at
    stall_first_seen_at zero_seeders_first_seen_at last_queue_state last_queue_health
  )a

  def up do
    alter table(:acquisition_pursuits) do
      for column <- @thread_columns, do: remove(column)
    end
  end

  def down do
    alter table(:acquisition_pursuits) do
      add :tried_release_guids, {:array, :string}, null: false, default: []
      add :attempt_count, :integer, null: false, default: 0
      add :current_target_id, :binary_id
      add :awaiting_decision_at, :utc_datetime
      add :stall_first_seen_at, :utc_datetime
      add :zero_seeders_first_seen_at, :utc_datetime
      add :last_queue_state, :string
      add :last_queue_health, :string
    end

    # Surgical inline restore paired with the column re-add above — the
    # rollback path of an expand/contract pair, not a data migration.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE acquisition_pursuits
    SET tried_release_guids = u.tried_release_guids,
        attempt_count = u.attempt_count,
        current_target_id = u.current_target_id,
        awaiting_decision_at = u.awaiting_decision_at,
        stall_first_seen_at = u.stall_first_seen_at,
        zero_seeders_first_seen_at = u.zero_seeders_first_seen_at,
        last_queue_state = u.last_queue_state,
        last_queue_health = u.last_queue_health
    FROM (
      SELECT pursuit_id, tried_release_guids, attempt_count, current_target_id,
             awaiting_decision_at, stall_first_seen_at, zero_seeders_first_seen_at,
             last_queue_state, last_queue_health,
             ROW_NUMBER() OVER (PARTITION BY pursuit_id ORDER BY position, inserted_at) AS rn
      FROM acquisition_pursuit_units
    ) AS u
    WHERE u.pursuit_id = acquisition_pursuits.id AND u.rn = 1
    """)
  end
end
