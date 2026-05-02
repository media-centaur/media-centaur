defmodule MediaCentarr.Repo.Migrations.AddLogoPathToReleaseTrackingItems do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      add :logo_path, :string
    end
  end
end
