defmodule MediaCentaur.Repo.Migrations.DropCollectionTitleIntents do
  @moduledoc """
  Deletes the title intents (and the tracked titles derived from them)
  that the library detail's collection-level tracking block wrote with a
  collection's `tmdb_collection` id stamped as a `:movie` ref (campaign
  title-detail-unification, decision 1b; tracking-controls spec
  2026-09-14, incoherence 12). Nothing read them: release tracking links
  tracked titles to series containers only, so a rung set on a
  collection fed no rail and no calendar, and the block is gone.

  A row is one of these when its `(tmdb_id, :movie)` equals the
  `tmdb_collection` external id of a library collection and no library
  movie carries that TMDB id — a real film sharing a collection's number
  is kept. Idempotent: a second run finds nothing. Down is a no-op — the
  rows are not recoverable, and the surface that wrote them no longer
  exists.
  """
  use Ecto.Migration

  @collection_ids """
  SELECT external_id FROM library_external_ids
  WHERE source = 'tmdb_collection' AND owner_type = 'movie_series'
  """

  @movie_ids """
  SELECT external_id FROM library_external_ids
  WHERE source = 'tmdb' AND owner_type = 'movie'
  """

  def up do
    execute """
    DELETE FROM release_tracking_releases WHERE item_id IN (
      SELECT id FROM release_tracking_items
      WHERE media_type = 'movie'
        AND CAST(tmdb_id AS TEXT) IN (#{@collection_ids})
        AND CAST(tmdb_id AS TEXT) NOT IN (#{@movie_ids})
    )
    """

    execute """
    DELETE FROM release_tracking_items
    WHERE media_type = 'movie'
      AND CAST(tmdb_id AS TEXT) IN (#{@collection_ids})
      AND CAST(tmdb_id AS TEXT) NOT IN (#{@movie_ids})
    """

    execute """
    DELETE FROM title_intents
    WHERE media_type = 'movie'
      AND CAST(tmdb_id AS TEXT) IN (#{@collection_ids})
      AND CAST(tmdb_id AS TEXT) NOT IN (#{@movie_ids})
    """
  end

  def down, do: :ok
end
