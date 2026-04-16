defmodule MediaCentarr.Repo.Migrations.AddInLibraryToReleases do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_releases) do
      add :in_library, :boolean, default: false, null: false
    end
  end
end
