defmodule MediaCentarr.Repo.Migrations.AddStatusToLibraryTypes do
  use Ecto.Migration

  def change do
    alter table(:library_tv_series) do
      add :status, :string
    end

    alter table(:library_movies) do
      add :status, :string
    end
  end
end
