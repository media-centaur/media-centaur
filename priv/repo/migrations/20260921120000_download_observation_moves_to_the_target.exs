defmodule MediaCentaur.Repo.Migrations.DownloadObservationMovesToTheTarget do
  @moduledoc """
  Moves download observation from the pursuit onto the **target**, and adds
  the fact that was missing entirely: `first_seen_in_queue_at`.

  A target is one grab of one release, which is exactly one download at the
  download client (`Pursuits.TargetUnit` — a release may cover many units, so
  a season pack's episodes already share one target). Observation therefore
  belongs to the target. Migration `20260612170000` moved it unit → pursuit to
  stop a 38-episode pack minting 38 identical `DownloadStarted` rows; that
  overshot, because an ADR-055 composite holds several torrents at once and
  pursuit-level observation tracked only the latest release title's.

  `first_seen_in_queue_at` is write-once and records the first snapshot in
  which the target's download was visible at the client. Its absence after a
  grab means *not at the client yet*; its presence with the download now gone
  means *left the client*. Before it existed, the view model inferred the
  latter from the former and read "Finished downloading" the instant a grab
  was handed off.

  The stall and zero-seeder windows move with it. They were unit columns for
  the same reason — `Policy` acts per unit — but they are readings of one
  download, so an N-unit pursuit wrote N identical rows per tick and could
  disagree with itself mid-pass. `Snapshots.build/4` already holds the unit's
  current target, so `Policy` reads them from there unchanged.

  Backfill: existing in-flight targets must not regress to "not at the client
  yet". A target is treated as already observed when it carries a
  `content_path` (only ever written from a live queue item) or when its
  pursuit carries a `last_queue_state`. `acquired_at` is the stamp used — the
  true first-observation time was never recorded, and `acquired_at` is the
  best lower bound available. Only presence is read, never the value.

  Single expand+backfill+drop rather than the expand/contract pair used at
  `20260612170000`: that precedent existed because the migration was hand-applied
  to a shared database while the old code still ran. Releases apply migrations
  at boot on the new code, so there is no window.
  """

  use Ecto.Migration

  def up do
    alter table(:acquisition_targets) do
      add :first_seen_in_queue_at, :utc_datetime
      add :last_queue_state, :string
      add :last_queue_health, :string
      add :stall_first_seen_at, :utc_datetime
      add :zero_seeders_first_seen_at, :utc_datetime
    end

    # Surgical fixup paired with the column addition — the seed values come
    # from the pursuit columns dropped below and must be captured here.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute """
    UPDATE acquisition_targets SET
      last_queue_state = (
        SELECT p.last_queue_state FROM acquisition_pursuits p
        WHERE p.id = acquisition_targets.pursuit_id
      ),
      last_queue_health = (
        SELECT p.last_queue_health FROM acquisition_pursuits p
        WHERE p.id = acquisition_targets.pursuit_id
      )
    WHERE acquisition_targets.status = 'acquired'
      AND acquisition_targets.release_title = (
        SELECT t.release_title FROM acquisition_targets t
        WHERE t.pursuit_id = acquisition_targets.pursuit_id
          AND t.release_title IS NOT NULL
        ORDER BY t.inserted_at DESC
        LIMIT 1
      )
    """

    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute """
    UPDATE acquisition_targets
    SET first_seen_in_queue_at = COALESCE(acquired_at, inserted_at)
    WHERE first_seen_in_queue_at IS NULL
      AND (
        content_path IS NOT NULL
        OR last_queue_state IS NOT NULL
      )
    """

    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute """
    UPDATE acquisition_targets SET
      stall_first_seen_at = (
        SELECT u.stall_first_seen_at FROM acquisition_pursuit_units u
        WHERE u.current_target_id = acquisition_targets.id
          AND u.stall_first_seen_at IS NOT NULL
        LIMIT 1
      ),
      zero_seeders_first_seen_at = (
        SELECT u.zero_seeders_first_seen_at FROM acquisition_pursuit_units u
        WHERE u.current_target_id = acquisition_targets.id
          AND u.zero_seeders_first_seen_at IS NOT NULL
        LIMIT 1
      )
    """

    alter table(:acquisition_pursuits) do
      remove :last_queue_state
      remove :last_queue_health
    end

    alter table(:acquisition_pursuit_units) do
      remove :stall_first_seen_at
      remove :zero_seeders_first_seen_at
    end
  end

  def down do
    alter table(:acquisition_pursuit_units) do
      add :stall_first_seen_at, :utc_datetime
      add :zero_seeders_first_seen_at, :utc_datetime
    end

    alter table(:acquisition_pursuits) do
      add :last_queue_state, :string
      add :last_queue_health, :string
    end

    alter table(:acquisition_targets) do
      remove :first_seen_in_queue_at
      remove :last_queue_state
      remove :last_queue_health
      remove :stall_first_seen_at
      remove :zero_seeders_first_seen_at
    end
  end
end
