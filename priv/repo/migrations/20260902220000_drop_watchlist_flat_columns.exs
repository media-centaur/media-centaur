defmodule MediaCentaur.Repo.Migrations.DropWatchlistFlatColumns do
  @moduledoc """
  Drops the flat title snapshot columns (`name`, `year`, `release_date`,
  `poster_path`, `overview`) from `watchlist_items`; the embedded `title`
  (added by `AddTitleEmbedToWatchlistItems`, filled by the
  `BackfillWatchlistTitleEmbed` data migration) is the whole record.

  Heals first, inline, exactly as that migration's moduledoc demands: the
  schema-migration stream runs before any data migration, so an install
  skipping the embed release reaches this drop with the backfill not yet
  run; and the outgoing release keeps serving between `migrate` and the
  restart, so it can still write a flat-only row. Either would leave
  `title` NULL, which the new code cannot render, and the columns it
  would be copied from are about to go.
  """
  use Ecto.Migration

  @heal """
  UPDATE watchlist_items
  SET title = json_object(
    'tmdb_id', tmdb_id,
    'media_type', media_type,
    'name', name,
    'year', year,
    'release_date', release_date,
    'poster_path', poster_path,
    'backdrop_path', NULL,
    'overview', overview
  )
  WHERE title IS NULL
  """

  def up do
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute(@heal)

    alter table(:watchlist_items) do
      remove :name
      remove :year
      remove :release_date
      remove :poster_path
      remove :overview
    end
  end

  def down do
    alter table(:watchlist_items) do
      add :name, :text
      add :year, :text
      add :release_date, :date
      add :poster_path, :text
      add :overview, :text
    end
  end
end
