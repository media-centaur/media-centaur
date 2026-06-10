defmodule MediaCentaur.Repo.Migrations.AddPlanTrackingFields do
  @moduledoc """
  Release-tracking-born plans (ADR-056 Phase 2): plans gain an origin
  ("manual" media-search default | "tracking") and a back-pointer to
  the tracking item (needed for cancel-dismisses and the one-active-
  draft-per-title rule; the tmdb id alone can't find the item for
  collection parts). Plan units gain a nullable per-unit quality floor
  — the patience elevation (`min := max` inside the want's window) is
  stamped here at plan creation so the planner needs no time concept.
  Additive; no backfill (existing plans are all manual).
  """
  use Ecto.Migration

  def change do
    alter table(:acquisition_plans) do
      add :origin, :string, null: false, default: "manual"
      add :tracking_item_id, :binary_id
    end

    alter table(:acquisition_plan_units) do
      add :min_quality, :string
    end

    create index(:acquisition_plans, [:origin, :status])
  end
end
