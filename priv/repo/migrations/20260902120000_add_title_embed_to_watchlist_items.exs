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

  That drop migration MUST run the same
  `UPDATE watchlist_items SET title = json_object(...) WHERE title IS NULL`
  inline — carrying the per-line carve-out
  `# credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration`
  — immediately before it `remove`s the columns. Two orderings demand it:
  the whole schema-migration stream runs before any data migration, so a
  user upgrading straight past this release reaches the drop with the
  backfill not yet run; and the installer keeps the outgoing release
  serving across both migration steps, so it can write a flat-only row
  (`title` NULL) after the data migration has already recorded success.
  Either leaves a NULL embed the new code cannot render.
  """
  use Ecto.Migration

  def change do
    alter table(:watchlist_items) do
      add :title, :map
    end
  end
end
