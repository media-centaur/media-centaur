defmodule MediaCentarr.Repo.Migrations.PursuitTargetRecipeRefactor do
  @moduledoc """
  Unifies pursuit/grab into pursuit (intent + recipe) + target (specific
  release attempt). Recipe lives on the pursuit so it survives across
  target attempts.

  Pursuit gains: `recipe_type ∈ {"tmdb","prowlarr_query"}`, `manual_query`,
  `current_target_id`. `tmdb_id` / `tmdb_type` become nullable (manual
  pursuits hold no TMDB metadata; the `"manual"` overload is gone).

  `acquisition_grabs` is renamed to `acquisition_targets`. Status values
  rename: `searching | snoozed → seeking`, `grabbed → acquired`,
  `abandoned → failed`. Recipe-level columns (`tmdb_id`, `tmdb_type`,
  `manual_query`, `season_number`, `episode_number`, `year`,
  `min_quality`, `max_quality`, `quality_4k_patience_hours`) move to
  the pursuit and are dropped from targets.
  """
  use Ecto.Migration

  def up do
    # ─── Pursuit: add recipe columns ────────────────────────────────────────
    alter table(:acquisition_pursuits) do
      add :recipe_type, :string, null: false, default: "tmdb"
      add :manual_query, :string
      add :current_target_id, :binary_id
    end

    # ─── Backfill recipe_type / manual_query from existing manual rows ──────
    # A pursuit is `prowlarr_query` if either its own `tmdb_type = 'manual'`
    # (legacy direct-insert path) or any of its linked grabs has
    # `tmdb_type = 'manual'` (manual_grabbed_changeset path). Manual query
    # text is sourced from the latest manual grab.
    execute("""
    UPDATE acquisition_pursuits
    SET recipe_type = 'prowlarr_query',
        manual_query = COALESCE(
          (
            SELECT g.manual_query
            FROM acquisition_grabs g
            WHERE g.pursuit_id = acquisition_pursuits.id
              AND g.manual_query IS NOT NULL
            ORDER BY g.inserted_at DESC
            LIMIT 1
          ),
          'unknown'
        )
    WHERE tmdb_type = 'manual'
       OR EXISTS (
         SELECT 1 FROM acquisition_grabs g
         WHERE g.pursuit_id = acquisition_pursuits.id
           AND g.tmdb_type = 'manual'
       )
    """)

    # ─── Drop the index that depends on tmdb_id / tmdb_type ─────────────────
    # We have to drop before relaxing the NOT NULL constraint so SQLite's
    # column-rename dance below can drop the originals.
    drop_if_exists index(:acquisition_pursuits, [
                     :tmdb_id,
                     :tmdb_type,
                     :season_number,
                     :episode_number
                   ])

    # ─── Relax NOT NULL on tmdb_id / tmdb_type via the SQLite rename dance ──
    # SQLite (≥ 3.35) supports DROP COLUMN; (≥ 3.25) supports RENAME COLUMN.
    # The dance: rename old → add new nullable → copy where TMDB → drop old.
    execute("ALTER TABLE acquisition_pursuits RENAME COLUMN tmdb_id TO tmdb_id_old")
    execute("ALTER TABLE acquisition_pursuits ADD COLUMN tmdb_id TEXT")

    execute("UPDATE acquisition_pursuits SET tmdb_id = tmdb_id_old WHERE recipe_type = 'tmdb'")

    execute("ALTER TABLE acquisition_pursuits DROP COLUMN tmdb_id_old")

    execute("ALTER TABLE acquisition_pursuits RENAME COLUMN tmdb_type TO tmdb_type_old")
    execute("ALTER TABLE acquisition_pursuits ADD COLUMN tmdb_type TEXT")

    execute(
      "UPDATE acquisition_pursuits SET tmdb_type = tmdb_type_old WHERE recipe_type = 'tmdb'"
    )

    execute("ALTER TABLE acquisition_pursuits DROP COLUMN tmdb_type_old")

    # Recreate the index (still useful for the TMDB lookup path).
    create index(:acquisition_pursuits, [
             :tmdb_id,
             :tmdb_type,
             :season_number,
             :episode_number
           ])

    create index(:acquisition_pursuits, [:recipe_type])

    # ─── Rename status values on acquisition_grabs ──────────────────────────
    # `searching` and `snoozed` both become `seeking` — Oban's `scheduled_at`
    # is the source of truth for "when will we try again", so the snooze
    # state doesn't need its own status value.
    execute(
      "UPDATE acquisition_grabs SET status = 'seeking' WHERE status IN ('searching', 'snoozed')"
    )

    execute("UPDATE acquisition_grabs SET status = 'acquired' WHERE status = 'grabbed'")
    execute("UPDATE acquisition_grabs SET status = 'failed' WHERE status = 'abandoned'")

    # `last_attempt_outcome = 'grabbed'` similarly migrates so the audit
    # trail stays consistent with the new vocabulary.
    execute(
      "UPDATE acquisition_grabs SET last_attempt_outcome = 'acquired' WHERE last_attempt_outcome = 'grabbed'"
    )

    # ─── Backfill current_target_id ─────────────────────────────────────────
    # Latest non-terminal target wins; if none, the latest target overall
    # (so the pursuit detail page still shows the most recent attempt).
    execute("""
    UPDATE acquisition_pursuits
    SET current_target_id = (
      SELECT g.id
      FROM acquisition_grabs g
      WHERE g.pursuit_id = acquisition_pursuits.id
      ORDER BY
        CASE g.status
          WHEN 'seeking' THEN 0
          WHEN 'acquired' THEN 0
          ELSE 1
        END,
        g.inserted_at DESC
      LIMIT 1
    )
    """)

    # ─── Drop indexes on acquisition_grabs that reference dropped columns ───
    drop_if_exists index(:acquisition_grabs, [:tmdb_id, :tmdb_type])

    drop_if_exists index(:acquisition_grabs, [
                     :tmdb_id,
                     :tmdb_type,
                     :season_number,
                     :episode_number
                   ])

    drop_if_exists index(:acquisition_grabs, [:tmdb_id, :tmdb_type],
                     name: :acquisition_grabs_tmdb_season_episode_index
                   )

    # ─── Rename table grabs → targets ───────────────────────────────────────
    rename table(:acquisition_grabs), to: table(:acquisition_targets)

    # ─── Rename timestamp: grabbed_at → acquired_at ─────────────────────────
    # The schema field follows the new vocabulary; the underlying SQLite
    # column has to follow.
    execute("ALTER TABLE acquisition_targets RENAME COLUMN grabbed_at TO acquired_at")

    # ─── Drop recipe-level columns from acquisition_targets ─────────────────
    alter table(:acquisition_targets) do
      remove :tmdb_id
      remove :tmdb_type
      remove :manual_query
      remove :season_number
      remove :episode_number
      remove :year
      remove :min_quality
      remove :max_quality
      remove :quality_4k_patience_hours
    end

    # New index by status (used by Acquisition.list_auto_targets/1).
    create_if_not_exists index(:acquisition_targets, [:status])
  end

  def down do
    raise Ecto.MigrationError,
          "irreversible — this refactor reshapes the pursuit + target schemas and renames the grab table; restore from backup if needed."
  end
end
