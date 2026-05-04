defmodule MediaCentarr.Repo.Migrations.AddTmdbIdToEntities do
  use Ecto.Migration

  def change do
    alter table(:library_tv_series) do
      add :tmdb_id, :string
    end

    alter table(:library_movie_series) do
      add :tmdb_id, :string
    end

    alter table(:library_video_objects) do
      add :tmdb_id, :string
    end
  end
end
