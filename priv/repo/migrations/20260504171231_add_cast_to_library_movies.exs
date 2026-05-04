defmodule MediaCentarr.Repo.Migrations.AddCastToLibraryMovies do
  use Ecto.Migration

  def change do
    alter table(:library_movies) do
      add :cast, :map
    end
  end
end
