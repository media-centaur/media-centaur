defmodule MediaCentaur.Repo.Migrations.AddOriginalTitleToPlansPursuitsAndItems do
  use Ecto.Migration

  # TMDB's canonical title for a foreign work is often the localised one
  # while release groups name the file after the original — or the other
  # way round. Carrying the original title lets the matcher accept
  # either name, and lets a movie search ask for both.
  #
  # Nullable with no backfill: snapshotted from TMDB at creation like
  # `origin_country` and the external ids, and self-healing on refresh
  # for tracking items.
  def change do
    alter table(:acquisition_plans) do
      add :original_title, :string
    end

    alter table(:acquisition_pursuits) do
      add :original_title, :string
    end

    alter table(:release_tracking_items) do
      add :original_title, :string
    end
  end
end
