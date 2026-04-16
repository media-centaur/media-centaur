defmodule MediaCentarr.Repo.Migrations.CreateAcquisitionGrabs do
  use Ecto.Migration

  def change do
    create table(:acquisition_grabs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tmdb_id, :string, null: false
      add :tmdb_type, :string, null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "searching"
      add :quality, :string
      add :attempt_count, :integer, null: false, default: 0
      add :grabbed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:acquisition_grabs, [:tmdb_id, :tmdb_type], unique: true)
    create index(:acquisition_grabs, [:status])
  end
end
