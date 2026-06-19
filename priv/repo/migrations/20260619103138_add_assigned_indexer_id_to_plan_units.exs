defmodule MediaCentaur.Repo.Migrations.AddAssignedIndexerIdToPlanUnits do
  use Ecto.Migration

  # The corpus candidate is the grab-ready rehydration source, but it ages
  # out of retention. Denormalize the indexer id onto the unit alongside the
  # other `assigned_*` fields so a plan approved after pruning can still grab
  # (Prowlarr requires a non-null integer indexerId). Nullable: pre-existing
  # rows stay nil and fall back to the grab guard.
  def change do
    alter table(:acquisition_plan_units) do
      add :assigned_indexer_id, :integer
    end
  end
end
