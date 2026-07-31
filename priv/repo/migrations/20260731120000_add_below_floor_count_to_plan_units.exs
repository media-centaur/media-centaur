defmodule MediaCentaur.Repo.Migrations.AddBelowFloorCountToPlanUnits do
  use Ecto.Migration

  # How many identity-verified releases exist for the unit below its
  # quality floor — stamped by the planner when nothing acceptable was
  # found, so the board can offer "lower quality available" instead of
  # a bare unfound. Additive with a default: safe on upgrade, reversible.
  def change do
    alter table(:acquisition_plan_units) do
      add :below_floor_count, :integer, null: false, default: 0
    end
  end
end
