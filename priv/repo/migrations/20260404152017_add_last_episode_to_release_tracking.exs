defmodule MediaCentaur.Repo.Migrations.AddLastEpisodeToReleaseTracking do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      add :last_library_season, :integer, null: false, default: 0
      add :last_library_episode, :integer, null: false, default: 0
    end
  end
end
