defmodule MediaCentarr.Repo.Migrations.CreateAcquisitionPursuitEvents do
  use Ecto.Migration

  def change do
    create table(:acquisition_pursuit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :pursuit_id,
          references(:acquisition_pursuits, type: :binary_id, on_delete: :nilify_all)

      add :denormalized_pursuit_title, :string, null: false
      add :kind, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:acquisition_pursuit_events, [:pursuit_id, :occurred_at])
    create index(:acquisition_pursuit_events, [:occurred_at])
    create index(:acquisition_pursuit_events, [:kind])
  end
end
