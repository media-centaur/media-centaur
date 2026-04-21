defmodule MediaCentarr.Repo.Migrations.AddLibrarySeasonsEpisodesFkIndexes do
  use Ecto.Migration

  # Rounds out the FK indexing started in 20260405173122_add_library_fk_indexes.
  # SQLite does not auto-create indexes for `references/2`, and the two
  # columns below drive every TV-series detail load:
  #
  #   - Library.list_seasons_by_owner_id/1     (where: season.tv_series_id == ^id)
  #   - Library.list_episodes_for_season/1     (where: episode.season_id == ^id)
  #   - Every preload of `seasons: :episodes`  (the preload runs one per-parent
  #                                             query, so the child-FK scan was
  #                                             the dominant cost without an index)
  def change do
    create index(:library_seasons, [:tv_series_id])
    create index(:library_episodes, [:season_id])
  end
end
