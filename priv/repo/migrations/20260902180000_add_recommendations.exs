defmodule MediaCentaur.Repo.Migrations.AddRecommendations do
  @moduledoc "Sent and received recommendations — one row per author + title; a newer event for the same address replaces the row."
  use Ecto.Migration

  def change do
    create table(:recommendations, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :event_id, :text, null: false
      add :author_pubkey, :text, null: false
      add :tmdb_id, :integer, null: false
      add :media_type, :text, null: false
      add :title, :map, null: false
      add :note, :text
      add :recommended_at, :utc_datetime, null: false
      add :raw_event, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:recommendations, [:event_id])
    create unique_index(:recommendations, [:author_pubkey, :tmdb_id, :media_type])
    create index(:recommendations, [:recommended_at])
  end
end
