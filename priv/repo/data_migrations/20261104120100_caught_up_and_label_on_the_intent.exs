defmodule MediaCentaur.Repo.DataMigrations.CaughtUpAndLabelOnTheIntent do
  @moduledoc """
  Moves what the schema migration of the same name made room for
  (campaign `discovery.md`, M16).

  1. **The start point out of the watermark.** A tracked series with no
     library container carried a caller's start point in
     `last_library_season/episode` — an authored fact in the library's
     columns — and `mark_in_library_releases/1` then flagged the episodes
     at or before it `in_library`. The pair moves to the intent's
     caught-up point (where the intent has none yet), the item's pair is
     zeroed, and the releases the pair had flagged are unflagged: the
     library holds none of them.
  2. **The label from the store.** Every intent whose title the store
     holds takes its name and year from the stored payload, so no existing
     record is a bare identity. The mapping (`name` or `title`; the year
     from `first_air_date` or `release_date`) is `TMDB.Title.from_tmdb/2`'s,
     frozen here as every migration freezes what it needs.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: step 1 matches only items whose pair is still set and
  intents whose point is still empty; step 2 only intents with no label.
  """
  use Ecto.Migration

  @unflag_releases """
  UPDATE release_tracking_releases SET in_library = 0, in_library_at = NULL
  WHERE in_library = 1 AND item_id IN (
    SELECT id FROM release_tracking_items
    WHERE media_type = 'tv_series' AND library_container_id IS NULL AND last_library_season > 0
  )
  """

  @move_point """
  UPDATE title_intents SET
    caught_up_season = (SELECT i.last_library_season FROM release_tracking_items i
                        WHERE i.tmdb_id = title_intents.tmdb_id AND i.media_type = title_intents.media_type),
    caught_up_episode = (SELECT i.last_library_episode FROM release_tracking_items i
                         WHERE i.tmdb_id = title_intents.tmdb_id AND i.media_type = title_intents.media_type)
  WHERE caught_up_season IS NULL AND media_type = 'tv_series' AND EXISTS (
    SELECT 1 FROM release_tracking_items i
    WHERE i.tmdb_id = title_intents.tmdb_id AND i.media_type = title_intents.media_type
      AND i.library_container_id IS NULL AND i.last_library_season > 0
  )
  """

  @zero_watermark """
  UPDATE release_tracking_items SET last_library_season = 0, last_library_episode = 0
  WHERE media_type = 'tv_series' AND library_container_id IS NULL AND last_library_season > 0
  """

  @label_from_store """
  UPDATE title_intents SET
    title_name = (SELECT COALESCE(json_extract(t.payload, '$.name'), json_extract(t.payload, '$.title'))
                  FROM tmdb_titles t
                  WHERE t.tmdb_id = title_intents.tmdb_id AND t.media_type = title_intents.media_type),
    title_year = (SELECT substr(COALESCE(json_extract(t.payload, '$.first_air_date'),
                                         json_extract(t.payload, '$.release_date')), 1, 4)
                  FROM tmdb_titles t
                  WHERE t.tmdb_id = title_intents.tmdb_id AND t.media_type = title_intents.media_type)
  WHERE title_name IS NULL AND EXISTS (
    SELECT 1 FROM tmdb_titles t
    WHERE t.tmdb_id = title_intents.tmdb_id AND t.media_type = title_intents.media_type
  )
  """

  def up, do: migrate(repo())

  def down, do: :ok

  @doc "The move, exposed for direct testing. Idempotent."
  def migrate(repo) do
    repo.query!(@unflag_releases)
    repo.query!(@move_point)
    repo.query!(@zero_watermark)
    repo.query!(@label_from_store)
    :ok
  end
end
