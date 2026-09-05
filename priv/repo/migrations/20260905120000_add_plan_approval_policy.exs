defmodule MediaCentaur.Repo.Migrations.AddPlanApprovalPolicy do
  use Ecto.Migration

  @moduledoc """
  Adds the per-plan approval policy: `automatic` (the Reactor gate
  commits the plan itself once it solves cleanly) or `review` (a person
  approves it on Downloads). Every existing row is either terminal
  (committed / discarded) or a user-facing draft, so `review` is the
  correct value for all of them — no backfill. Reversible: dropping the
  column loses nothing the gate can't re-derive for terminal rows.
  """

  def change do
    alter table(:acquisition_plans) do
      add :approval_policy, :string, null: false, default: "review"
    end
  end
end
