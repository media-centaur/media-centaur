defmodule MediaCentarr.Repo.Migrations.CreateReleaseTracking do
  use Ecto.Migration

  def change do
    create table(:release_tracking_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :media_type, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "watching"
      add :source, :string, null: false, default: "library"
      add :library_entity_id, :uuid
      add :last_refreshed_at, :utc_datetime
      add :poster_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:release_tracking_items, [:tmdb_id, :media_type],
             name: "release_tracking_items_tmdb_unique"
           )

    create table(:release_tracking_releases, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :delete_all),
        null: false

      add :air_date, :date
      add :title, :string
      add :season_number, :integer
      add :episode_number, :integer
      add :released, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:release_tracking_releases, [:item_id])
    create index(:release_tracking_releases, [:air_date])

    create table(:release_tracking_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :delete_all),
        null: false

      add :event_type, :string, null: false
      add :description, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:release_tracking_events, [:item_id])
  end
end
