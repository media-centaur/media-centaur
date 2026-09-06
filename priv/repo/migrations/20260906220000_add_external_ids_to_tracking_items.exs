defmodule MediaCentaur.Repo.Migrations.AddExternalIdsToTrackingItems do
  use Ecto.Migration

  # A tracked title's IMDb / TVDB spelling, so the drop planner can hand
  # it to the plans it creates — the automated acquisition path deserves
  # the same exact identity check the picker's plans get.
  #
  # Nullable with no backfill: the refresher self-heals every item from
  # its next TMDB response, exactly as it does for `origin_country`.
  def change do
    alter table(:release_tracking_items) do
      add :imdb_id, :string
      add :tvdb_id, :string
    end
  end
end
