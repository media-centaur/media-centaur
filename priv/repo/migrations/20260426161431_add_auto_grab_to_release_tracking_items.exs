defmodule MediaCentarr.Repo.Migrations.AddAutoGrabToReleaseTrackingItems do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      add :auto_grab_mode, :string, default: "global", null: false
      add :min_quality, :string
      add :max_quality, :string
      add :quality_4k_patience_hours, :integer
      add :prefer_season_packs, :boolean, default: false, null: false
    end
  end
end
