defmodule MediaCentaur.Repo.Migrations.AddNoCoverageFirstSeenAtToUnits do
  use Ecto.Migration

  # Observe-then-confirm timestamp for the LibraryReconciler's re-search
  # trigger: when a unit's grabbed release has landed but its own episode
  # is absent, this stamps the first observation so a confirmation window
  # can pass before pivoting (guards the import-window race). Mirrors the
  # existing stall_first_seen_at / zero_seeders_first_seen_at fields.
  # Additive, nullable — safe to apply and roll back.
  def change do
    alter table(:acquisition_pursuit_units) do
      add :no_coverage_first_seen_at, :utc_datetime
    end
  end
end
