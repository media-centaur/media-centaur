defmodule MediaCentaur.Repo.Migrations.CreateReleaseTrackingWants do
  @moduledoc """
  The want ledger (ADR-056 / release-tracking-plan-convergence campaign):
  durable per-unit acquisition intent owned by ReleaseTracking, distinct
  from `release_tracking_releases` (the wholesale-replaced TMDB calendar
  projection). A want opens when a unit becomes acquirable (aired and not
  in the library) and closes only by satisfaction or dismissal.

  No data backfill ships with this migration on purpose: `Wants.sync_item/1`
  is idempotent and runs on every refresher sweep, so the first post-deploy
  sweep populates the ledger from current calendar state (self-backfill).

  Also adds `part_tmdb_id` to the calendar table so movie/collection rows
  carry their own TMDB identity (the extractor already had it for
  collection parts; the helpers were dropping it).
  """
  use Ecto.Migration

  def change do
    create table(:release_tracking_wants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :item_id,
          references(:release_tracking_items, type: :binary_id, on_delete: :delete_all),
          null: false

      # Unit identity. TV wants carry season/episode; movie wants carry
      # part_tmdb_id. unit_key is the canonical dedup key ("s1e2" / "m603")
      # because SQLite treats NULLs as distinct in unique indexes — a
      # composite unique over the nullable identity columns would not
      # actually dedupe.
      add :unit_key, :string, null: false
      add :season_number, :integer
      add :episode_number, :integer
      add :part_tmdb_id, :integer
      add :title, :string
      add :air_date, :date

      add :status, :string, null: false, default: "open"
      add :provenance, :string, null: false, default: "calendar"

      add :wanted_since, :utc_datetime, null: false
      add :last_searched_at, :utc_datetime
      add :satisfied_at, :utc_datetime
      add :satisfied_quality, :string
      add :dismissed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:release_tracking_wants, [:item_id, :unit_key])
    create index(:release_tracking_wants, [:status])

    alter table(:release_tracking_releases) do
      add :part_tmdb_id, :integer
    end
  end
end
