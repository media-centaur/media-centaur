defmodule MediaCentaur.Repo.Migrations.CreateTmdbStore do
  @moduledoc """
  The TMDB store (campaign `tmdb-fetch-policy`, Phase 1; ADR-071): one
  row per TMDB title the app knows — the detail payload as TMDB returned
  it, the ETag to revalidate it with, when it was fetched and last
  changed, and the next event and check time
  `MediaCentaur.TMDB.Schedule` derives — plus one row per stored season.

  Additive; no backfill. Rows appear as titles are fetched
  (`MediaCentaur.TMDB.Client` writes through), and `next_check_at` is
  read by nothing until Phase 2 schedules checks.
  """
  use Ecto.Migration

  def change do
    create table(:tmdb_titles, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :media_type, :string, null: false
      add :tmdb_id, :integer, null: false
      add :payload, :map, null: false
      add :etag, :string
      add :fetched_at, :utc_datetime, null: false
      add :changed_at, :utc_datetime, null: false
      add :next_event_on, :date
      add :next_check_at, :utc_datetime
      add :settled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tmdb_titles, [:media_type, :tmdb_id])
    create index(:tmdb_titles, [:next_check_at])

    create table(:tmdb_seasons, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :season_number, :integer, null: false
      add :payload, :map, null: false
      add :etag, :string
      add :fetched_at, :utc_datetime, null: false
      add :changed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tmdb_seasons, [:tmdb_id, :season_number])
  end
end
