defmodule MediaCentarr.Repo.Migrations.AddReleaseTypeToReleases do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_releases) do
      add :release_type, :string
    end
  end
end
