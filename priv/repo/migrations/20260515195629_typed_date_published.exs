defmodule MediaCentarr.Repo.Migrations.TypedDatePublished do
  @moduledoc """
  Promotes `date_published` from `:string` to `:date` on the four container
  schemas (Movie, TVSeries, MovieSeries, VideoObject). See Phase 1 Task 2 of
  the Library Schema v2 campaign (`campaigns/library-schema-v2.md`).

  SQLite has no real column-type enforcement — it stores both `TEXT` and
  `DATE` as TEXT with the same on-disk format (ISO 8601 `"YYYY-MM-DD"` per
  `ecto_sqlite3`'s `:date` codec). The schema change is therefore a no-op
  at the SQL layer; only the Ecto field type changes, which alters how
  values are cast on read/write.

  The only data hazard is the empty-string sentinel some upstream paths
  used to write for "no date" — those fail `Date.from_iso8601/1`. The
  surgical fixup below normalizes them to NULL. Paired with the schema
  change, it qualifies as an inline fixup per ADR-040 / MC0015.

  The migration is forward-only: the `""` → `NULL` fixup is destructive of
  a sentinel value; rolling back wouldn't restore distinguishable state,
  so `down/0` is `:ok`.
  """
  use Ecto.Migration

  @tables [
    "library_movies",
    "library_tv_series",
    "library_movie_series",
    "library_video_objects"
  ]

  def up do
    for table <- @tables do
      # credo:disable-next-line MediaCentarr.Credo.Checks.RowMutationInSchemaMigration
      execute("UPDATE #{table} SET date_published = NULL WHERE date_published = ''")
    end
  end

  def down, do: :ok
end
