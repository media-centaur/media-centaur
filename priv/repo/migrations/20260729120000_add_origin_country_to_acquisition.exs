defmodule MediaCentaur.Repo.Migrations.AddOriginCountryToAcquisition do
  use Ecto.Migration

  @moduledoc """
  TMDB `origin_country` ISO codes for TV shows, threaded to every
  criteria builder so `Search.TitleMatcher` can accept scene country
  tags (`Title.US.S01`) on same-title remakes. Nullable with no
  backfill: rows created before this release read as "origin unknown"
  (tags rejected — prior behavior). Tracking items self-heal on their
  next metadata refresh.
  """

  def change do
    alter table(:acquisition_plans) do
      add :origin_country, {:array, :text}
    end

    alter table(:acquisition_pursuits) do
      add :origin_country, {:array, :text}
    end

    alter table(:release_tracking_items) do
      add :origin_country, {:array, :text}
    end
  end
end
