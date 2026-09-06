defmodule MediaCentaur.Repo.Migrations.AddExternalIdsToPlansAndPursuits do
  use Ecto.Migration

  # The want side of exact identity: a plan (and the pursuit it commits
  # to) knows the title it is chasing as a TMDB id, but indexers declare
  # their results with IMDb and TVDB ids. Carrying TMDB's spelling of
  # those lets `Search.TitleMatcher` settle identity by comparison
  # instead of by parsing the release name.
  #
  # Nullable with no backfill: the ids are snapshotted from TMDB at plan
  # creation, exactly as `origin_country` already is, and a row without
  # them keeps the title + ±1-year matching it has always had.
  def change do
    alter table(:acquisition_plans) do
      add :imdb_id, :string
      add :tvdb_id, :string
    end

    alter table(:acquisition_pursuits) do
      add :imdb_id, :string
      add :tvdb_id, :string
    end
  end
end
