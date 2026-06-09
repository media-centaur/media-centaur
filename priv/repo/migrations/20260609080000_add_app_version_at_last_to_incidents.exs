defmodule MediaCentaur.Repo.Migrations.AddAppVersionAtLastToIncidents do
  use Ecto.Migration

  # Tracks the app version at the *latest* occurrence of an incident (alongside
  # the existing `app_version_at_first`). The maintenance supersession sweep
  # uses it to auto-resolve open `:log` incidents that belong to a version no
  # longer running — a `:log` incident otherwise has no recovery signal and
  # stays open forever. Backfill existing rows from `app_version_at_first` so a
  # pre-migration incident has a sane "last seen on" value.
  def up do
    alter table(:incidents) do
      add :app_version_at_last, :string
    end

    # Surgical inline backfill paired with the column add (ADR-040): seeds the
    # new column from the existing one for pre-migration rows — a one-shot with
    # no logic, inseparable from the add, not a data migration.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute("UPDATE incidents SET app_version_at_last = app_version_at_first")
  end

  def down do
    alter table(:incidents) do
      remove :app_version_at_last
    end
  end
end
