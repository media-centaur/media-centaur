defmodule MediaCentaur.Repo.Migrations.DropOrphanedUnitQueueObservationColumns do
  @moduledoc """
  Contract phase of the expand/contract pair opened by
  `20260612170000_move_queue_observation_to_pursuit` (v0.90.3): drops
  `last_queue_state` / `last_queue_health` from
  `acquisition_pursuit_units`.

  The expand migration moved torrent lifecycle observation onto the
  pursuit — the tracked torrent is a pursuit-level fact, and observing
  it per unit multiplied every timeline event by the unit count. It
  deliberately left the unit columns in place because the shared
  dev/prod database is migrated while the *previous* release's code is
  still running, and that code kept writing them until the app
  restarted. It promised the drop to any release after v0.91; this is
  v1.12's.

  Nothing has mapped or written these columns since v0.90.3, so there is
  nothing to preserve going up. Down re-adds them and copies each
  pursuit's observation onto all of its units, which is the same shape
  the expand migration read on the way out (every unit of a pursuit
  observes the same torrent).
  """

  use Ecto.Migration

  def up do
    alter table(:acquisition_pursuit_units) do
      remove :last_queue_state
      remove :last_queue_health
    end
  end

  def down do
    alter table(:acquisition_pursuit_units) do
      add :last_queue_state, :string
      add :last_queue_health, :string
    end

    # Surgical inline restore paired with the column re-add above — the
    # rollback path of an expand/contract pair, not a data migration.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute """
    UPDATE acquisition_pursuit_units SET
      last_queue_state = (
        SELECT p.last_queue_state
        FROM acquisition_pursuits p
        WHERE p.id = acquisition_pursuit_units.pursuit_id
      ),
      last_queue_health = (
        SELECT p.last_queue_health
        FROM acquisition_pursuits p
        WHERE p.id = acquisition_pursuit_units.pursuit_id
      )
    """
  end
end
