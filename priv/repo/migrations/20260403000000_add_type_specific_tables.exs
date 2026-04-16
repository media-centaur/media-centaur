defmodule MediaCentarr.Repo.Migrations.AddTypeSpecificTables do
  use Ecto.Migration

  def change do
    # --- New type-specific tables ---

    create table(:library_tv_series, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :date_published, :text
      add :genres, {:array, :text}
      add :url, :text
      add :aggregate_rating_value, :float
      add :number_of_seasons, :bigint

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:library_movie_series, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :date_published, :text
      add :genres, {:array, :text}
      add :url, :text
      add :aggregate_rating_value, :float

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:library_video_objects, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :date_published, :text
      add :content_url, :text
      add :url, :text

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    # --- Add FK columns to existing tables ---

    # library_movies: movie_series_id FK + genres column
    alter table(:library_movies) do
      add :movie_series_id,
          references(:library_movie_series,
            column: :id,
            name: "library_movies_movie_series_id_fkey",
            type: :uuid
          )

      add :genres, {:array, :text}
    end

    # library_seasons: tv_series_id FK (coexists with entity_id during migration)
    alter table(:library_seasons) do
      add :tv_series_id,
          references(:library_tv_series,
            column: :id,
            name: "library_seasons_tv_series_id_fkey",
            type: :uuid
          )
    end

    # library_images: FKs for tv_series, movie_series, video_object
    alter table(:library_images) do
      add :tv_series_id,
          references(:library_tv_series,
            column: :id,
            name: "library_images_tv_series_id_fkey",
            type: :uuid
          )

      add :movie_series_id,
          references(:library_movie_series,
            column: :id,
            name: "library_images_movie_series_id_fkey",
            type: :uuid
          )

      add :video_object_id,
          references(:library_video_objects,
            column: :id,
            name: "library_images_video_object_id_fkey",
            type: :uuid
          )
    end

    # library_extras: FKs for movie, tv_series, movie_series
    alter table(:library_extras) do
      add :movie_id,
          references(:library_movies,
            column: :id,
            name: "library_extras_movie_id_fkey",
            type: :uuid
          )

      add :tv_series_id,
          references(:library_tv_series,
            column: :id,
            name: "library_extras_tv_series_id_fkey",
            type: :uuid
          )

      add :movie_series_id,
          references(:library_movie_series,
            column: :id,
            name: "library_extras_movie_series_id_fkey",
            type: :uuid
          )
    end

    # library_identifiers: FKs for movie, tv_series, movie_series, video_object
    alter table(:library_identifiers) do
      add :movie_id,
          references(:library_movies,
            column: :id,
            name: "library_identifiers_movie_id_fkey",
            type: :uuid
          )

      add :tv_series_id,
          references(:library_tv_series,
            column: :id,
            name: "library_identifiers_tv_series_id_fkey",
            type: :uuid
          )

      add :movie_series_id,
          references(:library_movie_series,
            column: :id,
            name: "library_identifiers_movie_series_id_fkey",
            type: :uuid
          )

      add :video_object_id,
          references(:library_video_objects,
            column: :id,
            name: "library_identifiers_video_object_id_fkey",
            type: :uuid
          )
    end

    # library_watched_files: FKs for movie, tv_series, movie_series, video_object
    alter table(:library_watched_files) do
      add :movie_id,
          references(:library_movies,
            column: :id,
            name: "library_watched_files_movie_id_fkey",
            type: :uuid
          )

      add :tv_series_id,
          references(:library_tv_series,
            column: :id,
            name: "library_watched_files_tv_series_id_fkey",
            type: :uuid
          )

      add :movie_series_id,
          references(:library_movie_series,
            column: :id,
            name: "library_watched_files_movie_series_id_fkey",
            type: :uuid
          )

      add :video_object_id,
          references(:library_video_objects,
            column: :id,
            name: "library_watched_files_video_object_id_fkey",
            type: :uuid
          )
    end

    # library_watch_progress: FKs for movie, episode, video_object
    alter table(:library_watch_progress) do
      add :movie_id,
          references(:library_movies,
            column: :id,
            name: "library_watch_progress_movie_id_fkey",
            type: :uuid
          )

      add :episode_id,
          references(:library_episodes,
            column: :id,
            name: "library_watch_progress_episode_id_fkey",
            type: :uuid
          )

      add :video_object_id,
          references(:library_video_objects,
            column: :id,
            name: "library_watch_progress_video_object_id_fkey",
            type: :uuid
          )
    end

    # --- Indexes ---

    # Partial unique indexes for image role uniqueness per type
    create unique_index(:library_images, [:tv_series_id, :role],
             name: "library_images_unique_tv_series_role_index"
           )

    create unique_index(:library_images, [:movie_series_id, :role],
             name: "library_images_unique_movie_series_role_index"
           )

    create unique_index(:library_images, [:video_object_id, :role],
             name: "library_images_unique_video_object_role_index"
           )
  end
end
