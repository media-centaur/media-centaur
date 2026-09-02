defmodule MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbed do
  @moduledoc """
  Fills `watchlist_items.title` (the embedded `TMDB.Title` JSON) from
  the flat snapshot columns for rows created before the embed existed.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: only rows whose `title` is NULL are touched. The JSON key
  set mirrors the embedded schema's fields exactly (`backdrop_path` was
  never a flat column, so it is NULL). `release_date` is stored as an
  ISO-8601 TEXT by the SQLite adapter, which is also how Ecto dumps a
  `:date` inside an embed, so the value copies through unchanged.

  Tolerates the flat columns being gone. At release boot the whole
  schema-migration stream runs before any data migration, so a user
  upgrading straight past the release that drops the flat columns
  reaches this file with `name`, `year`, `release_date`, `poster_path`
  and `overview` already removed — the UPDATE would fail with
  `no such column` and take the whole update down. When the columns are
  absent there is nothing to copy from, so this is a clean no-op. The
  drop migration carries its own inline copy of this backfill, which
  covers both that ordering and rows the outgoing release writes
  flat-only between `migrate` and the restart.
  """
  use Ecto.Migration

  @backfill """
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

  def up, do: backfill(repo())

  def down, do: :ok

  @doc """
  Backfill body, exposed for direct testing. Idempotent, and a no-op
  once the flat snapshot columns have been dropped.
  """
  def backfill(repo) do
    if flat_columns_present?(repo), do: repo.query!(@backfill)
    :ok
  end

  @doc "True while the flat snapshot columns this migration reads still exist."
  def flat_columns_present?(repo), do: column_present?(repo, "watchlist_items", "year")

  @doc """
  True when `table` has a column named `column`.

  `table` must be a literal table name — it is interpolated into the
  PRAGMA, which takes no bound parameters. Never pass user input.
  """
  def column_present?(repo, table, column) do
    %{rows: rows} = repo.query!("PRAGMA table_info(#{table})")

    # PRAGMA table_info returns [cid, name, type, notnull, dflt_value, pk].
    # The column name is at index 1; SQLite fixes this order, but if you
    # copy this helper, keep the index and this comment together.
    Enum.any?(rows, fn row -> Enum.at(row, 1) == column end)
  end
end
