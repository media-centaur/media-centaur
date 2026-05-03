defmodule MediaCentarr.Repo.Migrations.HealGrabsTmdbTypeTvSeries do
  use Ecto.Migration

  # An earlier release stored TV grabs with `tmdb_type = "tv_series"` (the
  # Ecto-stringified form of the `Item.media_type` enum) instead of the
  # TMDB-standard `"tv"` that `QueryBuilder.build/1` matches on. Affected
  # rows sat in `searching` state with `attempts: 0`, `last_attempt_at: nil`
  # while Oban silently retried — the worker raised `FunctionClauseError`
  # before any state-update code could record an attempt. The producer-side
  # bug is fixed in this release; this migration heals existing rows so they
  # progress on their next Oban wake.

  def up do
    # Drop "tv_series" rows that collide with a correct "tv" row for the
    # same release key. The "tv" row is authoritative (typically from a
    # user-driven bulk-arm); the "tv_series" duplicate is the auto-grab
    # bug's residue. Without this, the UPDATE below would hit the unique
    # index on (tmdb_id, tmdb_type, season_number, episode_number).
    execute("""
    DELETE FROM acquisition_grabs
    WHERE tmdb_type = 'tv_series'
      AND EXISTS (
        SELECT 1 FROM acquisition_grabs g2
        WHERE g2.tmdb_type = 'tv'
          AND g2.tmdb_id = acquisition_grabs.tmdb_id
          AND COALESCE(g2.season_number, -1) =
              COALESCE(acquisition_grabs.season_number, -1)
          AND COALESCE(g2.episode_number, -1) =
              COALESCE(acquisition_grabs.episode_number, -1)
      )
    """)

    execute("UPDATE acquisition_grabs SET tmdb_type = 'tv' WHERE tmdb_type = 'tv_series'")
  end

  def down do
    # Irreversible by design — this is a one-shot data correction, not a
    # schema change. The "tv_series" values were a bug; nothing legitimately
    # depends on the broken form.
    :ok
  end
end
