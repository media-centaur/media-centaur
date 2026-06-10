defmodule MediaCentaur.Repo.DataMigrations.BackfillUnitIdentity do
  @moduledoc """
  Copies parent-level `season_number` / `episode_number` from
  `acquisition_pursuits` onto each pursuit's units where the unit
  carries no identity of its own.

  The Phase-3 plans migration (`create_acquisition_plans`) added the
  unit identity columns additively with no backfill, so auto pursuits
  created before `Commands.Arm` started stamping units (campaign
  downloads-debt-retirement, item 3) have identity only on the parent.
  After this backfill, unit identity is complete everywhere and the
  unit-level readers (`CommitPlan` overlap check, `IdentityVerifier`
  description) no longer need a parent-level fallback.

  Idempotent — the UPDATE is gated on the unit's identity being NULL
  and the parent having one to give. Query-door pursuits (no parent
  identity) are untouched.

  This file is **append-only**. Never edit a shipped data migration.
  """
  use Ecto.Migration

  def up, do: backfill(repo())
  def down, do: :ok

  @doc "Backfill body, exposed for direct testing. Idempotent."
  def backfill(repo) do
    if table_exists?(repo, "acquisition_pursuit_units") do
      {:ok, _result} =
        repo.query("""
        UPDATE acquisition_pursuit_units
        SET season_number = (
              SELECT p.season_number FROM acquisition_pursuits p
              WHERE p.id = acquisition_pursuit_units.pursuit_id
            ),
            episode_number = (
              SELECT p.episode_number FROM acquisition_pursuits p
              WHERE p.id = acquisition_pursuit_units.pursuit_id
            )
        WHERE season_number IS NULL
          AND episode_number IS NULL
          AND EXISTS (
            SELECT 1 FROM acquisition_pursuits p
            WHERE p.id = acquisition_pursuit_units.pursuit_id
              AND (p.season_number IS NOT NULL OR p.episode_number IS NOT NULL)
          )
        """)
    end

    :ok
  end

  defp table_exists?(repo, table) do
    {:ok, %{rows: rows}} =
      repo.query(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table]
      )

    rows != []
  end
end
