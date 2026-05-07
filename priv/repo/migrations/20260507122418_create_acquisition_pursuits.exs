defmodule MediaCentarr.Repo.Migrations.CreateAcquisitionPursuits do
  use Ecto.Migration

  def change do
    create table(:acquisition_pursuits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :state, :string, null: false, default: "active"
      add :origin, :string, null: false
      add :tmdb_id, :string, null: false
      add :tmdb_type, :string, null: false
      add :title, :string, null: false
      add :year, :integer
      add :season_number, :integer
      add :episode_number, :integer
      add :criteria, :map, null: false, default: %{}
      add :tried_release_guids, {:array, :string}, null: false, default: []
      add :attempt_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:acquisition_pursuits, [:state])
    create index(:acquisition_pursuits, [:tmdb_id, :tmdb_type, :season_number, :episode_number])
  end
end
