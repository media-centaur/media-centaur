defmodule MediaCentarr.Repo.Migrations.AddWatchProgressCompletedLastWatchedIndex do
  use Ecto.Migration

  # Composite index on (completed, last_watched_at). Library.list_in_progress
  # and Library.list_hero_candidates both filter `completed = false` and order
  # by `last_watched_at` — without this index SQLite scans the table on every
  # call. Cheap to add; visible in EXPLAIN QUERY PLAN once present.
  def change do
    create index(:library_watch_progress, [:completed, :last_watched_at])
  end
end
