defmodule MediaCentaur.Repo.Migrations.AddReleaseTrackingItemSeasonSizes do
  @moduledoc """
  Fit gating for tracked shows: a tracking item gains `season_sizes` —
  how many episodes each of the show's seasons has, keyed by
  season-number string — recorded by the refresher from the TMDB
  responses it already fetches, and handed to every drop plan as its
  `span_sizes`. Without them the planner never judged a pack's fit for a
  weekly drop, so a season pack could be auto-grabbed for one new
  episode.

  Additive; no backfill. An item fills in on its next refresh (or at
  onboarding); until then its drop plans carry an empty map and plan
  exactly as before — gating is monotonic.
  """
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      add :season_sizes, :map, null: false, default: %{}
    end
  end
end
