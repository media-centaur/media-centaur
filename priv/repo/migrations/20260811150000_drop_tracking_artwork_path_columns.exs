defmodule MediaCentaur.Repo.Migrations.DropTrackingArtworkPathColumns do
  @moduledoc """
  Drops the tracked items' artwork path columns. Artwork for a TMDB
  identity resolves deterministically from the `TmdbArtwork` cache
  layout (`images/tmdb/{media_type}-{tmdb_id}/{role}.{ext}`), so the
  columns were a second representation of the same fact — every reader
  now goes through `TmdbArtwork.urls/2`, and the downloaders check disk
  instead of a column. The boot-time layout migration
  (`ReleaseTracking.migrate_artwork_layout_on_boot/1`) moves any legacy
  files; nothing needs the old column values.
  """
  use Ecto.Migration

  def change do
    alter table(:release_tracking_items) do
      remove :poster_path, :string
      remove :backdrop_path, :string
      remove :logo_path, :string
    end
  end
end
