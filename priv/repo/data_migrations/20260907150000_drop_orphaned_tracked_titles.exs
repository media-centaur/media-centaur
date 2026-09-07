defmodule MediaCentaur.Repo.DataMigrations.DropOrphanedTrackedTitles do
  @moduledoc """
  One-time sweep proving [ADR-065]'s invariant on existing data: every
  active tracked title is either owned or on the watchlist.

  This file is **append-only**. Never edit a shipped data migration.

  Before ADR-065, `detach_library_containers/1` nilled a deleted
  container's link and kept the row, so a series deleted from the library
  went on tracking — and, if the global mode allowed, on grabbing —
  whether or not anyone had asked. Those rows now have no tracking
  reason: no library link, no watchlist entry. They are what this
  deletes.

  Three exclusions, matching `ReleaseTracking.Reasons.retain?/1`:

    * a row still linked to a library container has the library reason;
    * a row whose `(tmdb_id, media_type)` is on the watchlist has the
      watchlist reason (the cutover migration synthesised those entries
      for every former `source = 'manual'` item);
    * a row at `tracking_mode = 'none'` carries an explicit disarm, which
      is durable and outlives every reason — deleting one would silently
      re-arm the title if it were ever re-acquired.

  The rule is expressed in SQL rather than by calling `Reasons` because a
  migration is a snapshot: live code rots out from under it. That is the
  sanctioned duplication for this stream, not a second representation of
  the rule.

  Idempotent: re-running finds nothing left to delete. Cascading rows
  (`release_tracking_releases`, `release_tracking_events`,
  `release_tracking_wants`) go with their item via the schema's FKs.

  [ADR-065]: `decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md`
  """
  use Ecto.Migration

  @sweep """
  DELETE FROM release_tracking_items
  WHERE library_container_id IS NULL
    AND tracking_mode <> 'none'
    AND NOT EXISTS (
      SELECT 1 FROM watchlist_items w
      WHERE w.tmdb_id = release_tracking_items.tmdb_id
        AND w.media_type = release_tracking_items.media_type
    )
  """

  def up, do: sweep(repo())

  def down, do: :ok

  @doc "Deletes every tracked title left with no tracking reason. Returns `:ok`."
  def sweep(repo) do
    repo.query!(@sweep, [])
    :ok
  end
end
