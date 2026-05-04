defmodule MediaCentarr.Repo.Migrations.DropTmdbExternalIds do
  @moduledoc """
  Drops `library_external_ids` rows for sources `"tmdb"` and `"tmdb_collection"`.

  The canonical TMDB id now lives in each entity's own `tmdb_id` column
  (see `20260504175757_add_tmdb_id_to_entities.exs` and the matching
  backfill). All readers (Inbound, ImageRepair, ReleaseTracking) have
  been switched over, so the duplicated rows are pure noise.

  `library_external_ids` continues to hold rows for non-TMDB sources
  (imdb, tvdb, etc.).
  """
  use Ecto.Migration

  def up do
    execute("DELETE FROM library_external_ids WHERE source IN ('tmdb', 'tmdb_collection')")
  end

  def down, do: :ok
end
