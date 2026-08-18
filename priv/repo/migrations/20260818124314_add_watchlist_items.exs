defmodule MediaCentaur.Repo.Migrations.AddWatchlistItems do
  use Ecto.Migration

  def change do
    create table(:watchlist_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :media_type, :text, null: false
      add :name, :text, null: false
      add :year, :text
      add :release_date, :date
      add :poster_path, :text
      add :overview, :text
      add :source, :text, null: false, default: "manual"
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:watchlist_items, [:tmdb_id, :media_type])
  end
end
