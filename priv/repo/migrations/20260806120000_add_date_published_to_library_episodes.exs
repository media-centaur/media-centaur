defmodule MediaCentaur.Repo.Migrations.AddDatePublishedToLibraryEpisodes do
  use Ecto.Migration

  # Episodes carried a `date_published` all the way through the detail
  # projection (`DetailItem.Episode` → `episode_to_map/1` → the detail
  # panel), but the column never existed, so the projection hardcoded
  # `nil` and every consumer silently rendered no air date. TMDB returns
  # `air_date` on each episode object, so the value was there for the
  # taking — this adds the column the rest of the chain already assumed.
  #
  # No backfill: air dates arrive with the next metadata fetch for a
  # series. Existing rows stay `nil`, which is the same thing the
  # projection was already producing, so nothing regresses.
  def change do
    alter table(:library_episodes) do
      add :date_published, :date
    end
  end
end
