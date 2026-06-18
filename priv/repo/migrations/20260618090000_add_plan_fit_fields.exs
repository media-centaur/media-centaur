defmodule MediaCentaur.Repo.Migrations.AddPlanFitFields do
  @moduledoc """
  Fit-aware planning (the "don't grab a whole series for one episode"
  fix): plans gain `span_sizes` — the per-season aired-episode counts
  captured from the targeting selection — which the planner uses as the
  fit denominator (`wanted-in-span / span-total`) to decide whether a
  season/series pack is worth its over-grab. Plan units gain the
  fit-gated *offer* fields: when only an over-broad pack covers an
  unfound unit, the pack is surfaced here (not auto-assigned) so the
  board can spell out the over-grab and let the user opt in.

  Additive; no backfill. Plans without `span_sizes` (movies, legacy,
  tracking drops) plan exactly as before — gating is monotonic.
  """
  use Ecto.Migration

  def change do
    alter table(:acquisition_plans) do
      add :span_sizes, :map, null: false, default: %{}
    end

    alter table(:acquisition_plan_units) do
      add :offered_guid, :string
      add :offered_title, :string
      add :offered_scope, :string
      add :offered_size_bytes, :integer
    end
  end
end
