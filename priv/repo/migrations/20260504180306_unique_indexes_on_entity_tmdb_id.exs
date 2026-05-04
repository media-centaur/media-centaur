defmodule MediaCentarr.Repo.Migrations.UniqueIndexesOnEntityTmdbId do
  use Ecto.Migration

  def change do
    create unique_index(:library_movies, [:tmdb_id], where: "tmdb_id IS NOT NULL")
    create unique_index(:library_tv_series, [:tmdb_id], where: "tmdb_id IS NOT NULL")
    create unique_index(:library_movie_series, [:tmdb_id], where: "tmdb_id IS NOT NULL")
    create unique_index(:library_video_objects, [:tmdb_id], where: "tmdb_id IS NOT NULL")
  end
end
