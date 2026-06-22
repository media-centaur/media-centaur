defmodule MediaCentaur.Repo.Migrations.AddAirDateToPlanUnits do
  use Ecto.Migration

  # The cour-aware coverage guard compares a candidate's publish date
  # against each wanted episode's air date, so the guard (which runs in
  # the RunPlan Oban worker off a reloaded row) needs the per-unit air
  # date denormalized onto the plan unit. Raw episode data, populated at
  # plan creation from the want / selection episodes — not the derived
  # cour model (that stays recomputed on demand). Nullable: pre-existing
  # rows and movie units stay nil and the guard no-ops for them.
  def change do
    alter table(:acquisition_plan_units) do
      add :air_date, :date
    end
  end
end
