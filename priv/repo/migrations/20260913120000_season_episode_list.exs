defmodule MediaCentaur.Repo.Migrations.SeasonEpisodeList do
  @moduledoc """
  A season's episode list replaces its episode count. `number_of_episodes`
  was `length(episodes)` over the TMDB `get_season` payload, which the
  ingest stage discarded; `episode_list` keeps `episode_number`, `name` and
  `air_date` for every episode the season has, so the detail modal can tell
  a missing episode from one that has not aired without asking TMDB
  (2026-09-13 series-gap-download design).

  No data migration. The column is a snapshot of an external source and
  cannot be derived from anything local — *Refresh episode lists* under
  Settings → Maintenance repopulates it, one `get_season` per incomplete
  season. Until it runs a season carries an empty list, and the season list
  renders exactly as it did before.
  """
  use Ecto.Migration

  def change do
    alter table(:library_seasons) do
      add :episode_list, :map
      remove :number_of_episodes, :integer
    end
  end
end
