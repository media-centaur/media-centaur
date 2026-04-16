defmodule MediaCentarr.Repo.Migrations.AddBackdropPathToTrackingItems do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      add :backdrop_path, :string
    end
  end
end
