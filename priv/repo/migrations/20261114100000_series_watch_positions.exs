defmodule MediaCentaur.Repo.Migrations.SeriesWatchPositions do
  @moduledoc """
  Records where a profile is in a series: the order key of the last item
  playback finished (`MediaCentaur.Library.SeriesWatchPosition`).

  `series_id` carries no foreign key — a series is a `tv_series` or a
  `movie_series` row, told apart by `series_type` — so `EntityCascade`
  removes the rows with their series, and `series_id` has an index of its
  own for that delete. The FK to `profiles` cascades.

  The table is filled from the existing item progress rows by the data
  migration of the same name.
  """
  use Ecto.Migration

  def up do
    create table(:library_series_watch_positions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :series_type, :string, null: false
      add :series_id, :binary_id, null: false
      add :order_key, {:array, :string}, null: false
      add :finished_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:library_series_watch_positions, [:profile_id, :series_id])
    create index(:library_series_watch_positions, [:series_id])
  end

  def down do
    drop table(:library_series_watch_positions)
  end
end
