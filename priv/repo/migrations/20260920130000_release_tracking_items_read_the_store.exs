defmodule MediaCentaur.Repo.Migrations.ReleaseTrackingItemsReadTheStore do
  @moduledoc """
  A tracked item stops copying TMDB facts (campaign `tmdb-fetch-policy`
  Phase 2, ADR-071): name, year, imdb_id, tvdb_id, original_title,
  origin_country, season_sizes and last_refreshed_at were written by the
  refresher from every fetch and are now read from the TMDB store, which
  `TMDB.CheckJob` fills at boot for every tracked title the store lacks.
  The refresher's two interval settings and its sweep anchor go with it;
  the rows are orphans once the code that read them is gone, so the
  deletes are idempotent.

  `down/0` restores the columns empty: nothing refills them, since the
  refresher that did no longer exists.
  """
  use Ecto.Migration

  @columns [
    :name,
    :year,
    :imdb_id,
    :tvdb_id,
    :original_title,
    :origin_country,
    :season_sizes,
    :last_refreshed_at
  ]

  @settings_keys [
    "release_tracking_refresh_interval_hours",
    "release_tracking_sweep_interval_minutes",
    "release_tracking:last_swept_at"
  ]

  def up do
    alter table(:release_tracking_items) do
      for column <- @columns, do: remove(column)
    end

    execute(fn ->
      for key <- @settings_keys do
        repo().query!("DELETE FROM settings_entries WHERE key = ?", [key])
      end
    end)
  end

  def down do
    alter table(:release_tracking_items) do
      add :name, :string
      add :year, :integer
      add :imdb_id, :string
      add :tvdb_id, :string
      add :original_title, :string
      add :origin_country, {:array, :string}
      add :season_sizes, :map, null: false, default: %{}
      add :last_refreshed_at, :utc_datetime
    end
  end
end
