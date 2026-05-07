defmodule MediaCentarr.Repo.Migrations.ExtendAcquisitionGrabsForPursuits do
  use Ecto.Migration

  def change do
    alter table(:acquisition_grabs) do
      add :pursuit_id,
          references(:acquisition_pursuits, type: :binary_id, on_delete: :nilify_all)

      add :excluded_release_guids, {:array, :string}, null: false, default: []
    end

    create index(:acquisition_grabs, [:pursuit_id])
  end
end
