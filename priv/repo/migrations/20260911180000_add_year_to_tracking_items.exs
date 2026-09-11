defmodule MediaCentaur.Repo.Migrations.AddYearToTrackingItems do
  use Ecto.Migration

  # A tracked movie's release year, so the automated drop planner can hand
  # it to the plans it creates. Without it the movie year gate is inert —
  # `TitleMatcher.year_matches?/2` tolerates anything against a nil year,
  # which is how a 2026 film satisfied a want for a 2020 one.
  #
  # The drop planner previously read the year off `Want.air_date`: scope
  # answering an identity question, and nil whenever the calendar row was
  # thin. The year belongs to the title, so it lives on the title.
  #
  # Nullable with no backfill: the refresher self-heals every item from its
  # next TMDB response, exactly as it does for `origin_country` and the
  # external ids.
  def change do
    alter table(:release_tracking_items) do
      add :year, :integer
    end
  end
end
