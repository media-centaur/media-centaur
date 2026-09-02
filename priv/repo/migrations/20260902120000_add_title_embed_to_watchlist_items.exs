defmodule MediaCentaur.Repo.Migrations.AddTitleEmbedToWatchlistItems do
  @moduledoc """
  Watchlist rows carry their TMDB title as one embedded value
  (`MediaCentaur.TMDB.Title`, JSON in a `:map` column) instead of five
  flat snapshot columns. The identity columns (`tmdb_id`, `media_type`)
  stay for the unique index and are derived from the embed on write.

  Paired with the `BackfillWatchlistTitleEmbed` data migration, which
  fills `title` from the flat columns. The flat snapshot columns
  (`name`, `year`, `release_date`, `poster_path`, `overview`) are dropped
  by a later release's migration once every install has backfilled;
  until then `name` (NOT NULL) is still written from the embed.
  """
  use Ecto.Migration

  def change do
    alter table(:watchlist_items) do
      add :title, :map
    end
  end
end
