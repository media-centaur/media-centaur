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

  @doc "Backfill body, exposed for direct testing. Idempotent."
  def backfill(repo) do
    repo.query!(@backfill)
    :ok
  end
end
