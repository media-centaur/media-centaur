defmodule MediaCentarr.Repo.Migrations.DropEntityTable do
  use Ecto.Migration

  def up do
    # Drop ALL indexes that reference entity_id (SQLite requires this before column drop)
    drop_if_exists index(:library_movies, [], name: "movies_unique_entity_movie_index")
    drop_if_exists index(:library_seasons, [], name: "seasons_unique_entity_season_index")
    drop_if_exists index(:library_images, [], name: "images_unique_entity_role_index")
    drop_if_exists index(:library_extras, [], name: "extras_unique_entity_extra_index")
    drop_if_exists index(:library_identifiers, [], name: "identifiers_entity_id_index")
    drop_if_exists index(:library_watched_files, [], name: "watched_files_entity_id_index")

    drop_if_exists index(:library_watch_progress, [],
                     name: "watch_progress_unique_playable_item_index"
                   )

    drop_if_exists index(:pipeline_image_queue, [], name: "pipeline_image_queue_entity_id_index")

    # Remove entity_id columns from all tables
    alter table(:library_movies) do
      remove :entity_id
    end

    alter table(:library_seasons) do
      remove :entity_id
    end

    alter table(:library_images) do
      remove :entity_id
    end

    alter table(:library_extras) do
      remove :entity_id
    end

    alter table(:library_identifiers) do
      remove :entity_id
    end

    alter table(:library_watched_files) do
      remove :entity_id
    end

    alter table(:library_watch_progress) do
      remove :entity_id
      remove :season_number
      remove :episode_number
    end

    alter table(:library_extra_progress) do
      remove :entity_id
    end

    # Drop Entity table
    drop table(:library_entities)
  end

  def down do
    raise "Irreversible — cannot recreate Entity table with data"
  end
end
