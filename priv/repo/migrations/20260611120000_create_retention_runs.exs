defmodule MediaCentaur.Repo.Migrations.CreateRetentionRuns do
  @moduledoc """
  One upserted row per retention policy recording its pruning behavior:
  when the policy last ran, how many rows/files it removed on that run,
  and the lifetime total. Surfaced on the Status page so every retention
  policy's effect is visible. Additive; no backfill.
  """
  use Ecto.Migration

  def change do
    create table(:retention_runs, primary_key: false) do
      add :policy_key, :string, primary_key: true
      add :last_ran_at, :utc_datetime, null: false
      add :pruned_last_run, :integer, null: false, default: 0
      add :pruned_total, :bigint, null: false, default: 0
    end
  end
end
