defmodule MediaCentaur.Repo.Migrations.AddPlanUnitAssignedSize do
  use Ecto.Migration

  def change do
    alter table(:acquisition_plan_units) do
      add :assigned_size_bytes, :integer
    end
  end
end
