defmodule MediaCentarr.Repo.Migrations.DurationSecondsInteger do
  @moduledoc """
  Replaces the stringly-typed `duration` column on `library_movies` and
  `library_episodes` with the canonical `duration_seconds :integer`. See
  Phase 1 Task 3 of the Library Schema v2 campaign
  (`campaigns/library-schema-v2.md`).

  Prior to this migration, `duration` stored an ambiguous mix of formats —
  ISO 8601 (`"PT2H30M"`), bare minute strings (`"150"`), and free-text
  (`"150 min"`). The canonical replacement is integer seconds, computed at
  the TMDB boundary (`TMDB.Mapper`) from `runtime` (minutes).

  `ecto_sqlite3` does not implement column-type `modify`. Because the
  existing string values cannot be reliably parsed (the format is
  ambiguous) and the metadata is rebuildable from TMDB on next ingest /
  refresh, the migration drops the old column and adds the new one
  empty. Re-ingestion repopulates `duration_seconds`.

  The migration is destructive of prior `duration` values; the `down/0`
  restores the column shape but cannot restore content.
  """
  use Ecto.Migration

  def up do
    alter table(:library_movies) do
      remove :duration
      add :duration_seconds, :integer
    end

    alter table(:library_episodes) do
      remove :duration
      add :duration_seconds, :integer
    end
  end

  def down do
    alter table(:library_movies) do
      remove :duration_seconds
      add :duration, :string
    end

    alter table(:library_episodes) do
      remove :duration_seconds
      add :duration, :string
    end
  end
end
