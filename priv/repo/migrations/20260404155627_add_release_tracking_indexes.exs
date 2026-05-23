defmodule MediaCentaur.Repo.Migrations.AddReleaseTrackingIndexes do
  use Ecto.Migration

  def change do
    create index(:release_tracking_items, [:status])
    create index(:release_tracking_items, [:library_entity_id])
  end
end
