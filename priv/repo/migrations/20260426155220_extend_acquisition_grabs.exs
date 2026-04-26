defmodule MediaCentarr.Repo.Migrations.ExtendAcquisitionGrabs do
  use Ecto.Migration

  def change do
    alter table(:acquisition_grabs) do
      add :season_number, :integer
      add :episode_number, :integer
      add :year, :integer
      add :last_attempt_at, :utc_datetime
      add :last_attempt_outcome, :string
      add :cancelled_at, :utc_datetime
      add :cancelled_reason, :string
    end

    drop unique_index(:acquisition_grabs, [:tmdb_id, :tmdb_type])

    create unique_index(
             :acquisition_grabs,
             [:tmdb_id, :tmdb_type, :season_number, :episode_number],
             name: :acquisition_grabs_tmdb_season_episode_index
           )
  end
end
