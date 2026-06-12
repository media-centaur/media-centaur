defmodule MediaCentaur.Repo.Migrations.MoveQueueObservationToPursuit do
  @moduledoc """
  Moves the torrent lifecycle observation (`last_queue_state`,
  `last_queue_health`) from units to the pursuit. The tracked torrent is
  a pursuit-level fact shared by every unit of a composite pursuit;
  per-unit observation multiplied every timeline event by the unit
  count.

  **Expand phase only** (expand/contract): the now-unmapped unit columns
  are deliberately NOT dropped here — the previous release's code still
  writes them until the app restarts on the new code, and this
  migration is applied to the shared dev/prod DB while that code runs.
  A future release ships the contract migration dropping
  `acquisition_pursuit_units.last_queue_state` /
  `acquisition_pursuit_units.last_queue_health`.

  Backfill copies any unit's current observation onto its pursuit
  (units of one pursuit all observe the same torrent, so any non-null
  row is authoritative) — without it, in-flight downloads would re-emit
  a spurious "Download started" on the first tick after upgrade.
  `NULLIF(…, 'nil')` also retires the literal "nil" strings the old
  `Atom.to_string/1` stringification wrote.
  """

  use Ecto.Migration

  def up do
    alter table(:acquisition_pursuits) do
      add :last_queue_state, :string
      add :last_queue_health, :string
    end

    # Surgical fixup paired with the column addition above — the seed
    # values come from the legacy unit columns and must be captured at
    # the same point the new columns appear.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute """
    UPDATE acquisition_pursuits SET
      last_queue_state = (
        SELECT NULLIF(u.last_queue_state, 'nil')
        FROM acquisition_pursuit_units u
        WHERE u.pursuit_id = acquisition_pursuits.id
          AND u.last_queue_state IS NOT NULL
        LIMIT 1
      ),
      last_queue_health = (
        SELECT NULLIF(u.last_queue_health, 'nil')
        FROM acquisition_pursuit_units u
        WHERE u.pursuit_id = acquisition_pursuits.id
          AND u.last_queue_state IS NOT NULL
        LIMIT 1
      )
    """
  end

  def down do
    alter table(:acquisition_pursuits) do
      remove :last_queue_state
      remove :last_queue_health
    end
  end
end
