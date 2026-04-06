defmodule MediaCentaur.Repo.Migrations.AddDismissReleasedBeforeToItems do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      add :dismiss_released_before, :date
    end
  end
end
