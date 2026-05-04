defmodule MediaCentarr.Repo.Migrations.AddCrewAndImdbIdToMovies do
  @moduledoc """
  Adds `crew` (JSON array of structured crew entries) and `imdb_id`
  columns to `library_movies`. Powers the More info detail panel:
  director(s), writers, composer, etc. with TMDB-person ids preserved
  for linking, plus an external link to IMDb.

  No backfill — `Maintenance.refresh_movie_credits/0` is the user-driven
  refresh path that populates these for existing rows from TMDB.
  """
  use Ecto.Migration

  def change do
    alter table(:library_movies) do
      add :crew, :map
      add :imdb_id, :string
    end
  end
end
