defmodule MediaCentaur.Repo.Migrations.CreateWatchHistoryEvents do
  use Ecto.Migration

  def change do
    create table(:watch_history_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :entity_type, :string, null: false
      add :title, :string, null: false
      add :duration_seconds, :float, null: false, default: 0.0
      add :completed_at, :utc_datetime, null: false

      add :movie_id, references(:library_movies, type: :uuid, on_delete: :nilify_all)
      add :episode_id, references(:library_episodes, type: :uuid, on_delete: :nilify_all)

      add :video_object_id,
          references(:library_video_objects, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:watch_history_events, [:completed_at])
    create index(:watch_history_events, [:entity_type])
    create index(:watch_history_events, [:movie_id])
    create index(:watch_history_events, [:episode_id])
    create index(:watch_history_events, [:video_object_id])
  end
end
