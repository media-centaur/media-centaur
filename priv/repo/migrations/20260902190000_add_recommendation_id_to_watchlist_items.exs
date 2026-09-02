defmodule MediaCentaur.Repo.Migrations.AddRecommendationIdToWatchlistItems do
  @moduledoc """
  Provenance for a watchlist item added from the recommendations feed: the
  id of the `recommendations` row it came from.

  A bare uuid, not a foreign key — `Discovery` and `Recommendations` are
  independent bounded contexts and neither may reference the other's
  tables. Nullable, no backfill: every existing row is `source: :manual`
  and carries none.
  """
  use Ecto.Migration

  def change do
    alter table(:watchlist_items) do
      add :recommendation_id, :uuid
    end
  end
end
