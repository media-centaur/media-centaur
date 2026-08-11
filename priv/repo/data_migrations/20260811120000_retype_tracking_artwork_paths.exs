defmodule MediaCentaur.Repo.DataMigrations.RetypeTrackingArtworkPaths do
  @moduledoc """
  Rewrites tracked items' artwork path columns from the bare-id legacy
  layout (`images/tracking/{tmdb_id}/…`) to the media-type-keyed
  TmdbArtwork layout (`images/tmdb/{media_type}-{tmdb_id}/…`). The
  media type comes from the row itself, so the rewrite is pure SQL.

  Pairs with the boot-time disk move
  (`ReleaseTracking.migrate_artwork_layout_on_boot/1`), which renames
  the directories to match.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: each UPDATE only touches rows still carrying the legacy
  prefix.
  """
  use Ecto.Migration

  def up, do: retype_paths(repo())

  def down, do: :ok

  @doc """
  Rewrite body, exposed for direct testing. Idempotent — re-runs are
  no-ops once no legacy prefixes remain.
  """
  def retype_paths(repo) do
    for {column, filename} <- [
          {"poster_path", "poster.jpg"},
          {"backdrop_path", "backdrop.jpg"},
          {"logo_path", "logo.png"}
        ] do
      repo.query!("""
      UPDATE release_tracking_items
      SET #{column} = 'images/tmdb/' || media_type || '-' || tmdb_id || '/#{filename}'
      WHERE #{column} LIKE 'images/tracking/%'
      """)
    end

    :ok
  end
end
