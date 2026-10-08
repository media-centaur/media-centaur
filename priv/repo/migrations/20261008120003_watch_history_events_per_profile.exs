defmodule MediaCentaur.Repo.Migrations.WatchHistoryEventsPerProfile do
  @moduledoc """
  A completion is a profile's (ADR-078, phase 2). Rebuild
  `watch_history_events` with `profile_id`, every existing event the
  oldest profile's, indexed on `(profile_id, completed_at)` for the
  History page's newest-first list. The copy fills the column, so no
  UPDATE. The entity FKs stay `nilify_all` (the table is append-only
  history). Not reversible.
  """
  use Ecto.Migration

  def up do
    create table(:watch_history_events_next, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :entity_type, :text, null: false
      add :title, :text, null: false
      add :duration_seconds, :float, null: false, default: 0.0
      add :completed_at, :utc_datetime_usec, null: false

      add :movie_id, references(:library_movies, type: :uuid, on_delete: :nilify_all)
      add :episode_id, references(:library_episodes, type: :uuid, on_delete: :nilify_all)

      add :video_object_id,
          references(:library_video_objects, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    execute """
    INSERT INTO watch_history_events_next
      (id, profile_id, entity_type, title, duration_seconds, completed_at,
       movie_id, episode_id, video_object_id, inserted_at, updated_at)
    SELECT id, (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1), entity_type, title,
           duration_seconds, completed_at, movie_id, episode_id, video_object_id,
           inserted_at, updated_at
    FROM watch_history_events
    """

    drop table(:watch_history_events)
    rename table(:watch_history_events_next), to: table(:watch_history_events)

    create index(:watch_history_events, [:profile_id, :completed_at])
    create index(:watch_history_events, [:completed_at])
    create index(:watch_history_events, [:entity_type])
    create index(:watch_history_events, [:movie_id])
    create index(:watch_history_events, [:episode_id])
    create index(:watch_history_events, [:video_object_id])
  end

  def down do
    raise Ecto.MigrationError,
          "watch_history_events_per_profile is not reversible — the profile of each event would be lost"
  end
end
