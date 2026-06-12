defmodule MediaCentaur.Repo.Migrations.HealDataMigrationsTracking do
  @moduledoc """
  Moves mis-tracked data-migration versions out of `schema_migrations`
  into the dedicated `data_migrations` table.

  `MediaCentaur.DataMigrations.run!/1` originally passed
  `migration_source:` as an option to `Ecto.Migrator.run/4`, which
  ecto_sql silently ignores — the versions-table name is read from repo
  config only. Every data migration shipped before 2026-06-12 was
  therefore recorded in `schema_migrations`. This migration heals
  existing installs in lockstep with the runner fix
  (`with_data_migration_source/2`): without it, the fixed runner would
  see an empty `data_migrations` table and replay all shipped data
  migrations on the next deploy.

  Idempotent: `INSERT OR IGNORE` plus `WHERE version IN (...)` make a
  re-run a no-op for any subset of already-healed rows. On fresh
  installs the data-migration versions were never in
  `schema_migrations`, so this only creates the (empty) tracking table.
  """
  use Ecto.Migration

  # Every data migration shipped while the runner tracked versions in
  # schema_migrations. Frozen list — data migrations shipped after the
  # runner fix are tracked correctly from the start.
  @mistracked_versions [
    20_260_509_120_000,
    20_260_517_100_100,
    20_260_517_110_200,
    20_260_610_144_619,
    20_260_610_220_000
  ]

  def up do
    versions = Enum.join(@mistracked_versions, ", ")

    # Same shape ecto_sql creates for its versions table; created here so
    # the copy below works even though the data migrator (which would
    # normally create it) hasn't run yet at this point in the boot order.
    execute """
    CREATE TABLE IF NOT EXISTS data_migrations (
      version INTEGER PRIMARY KEY,
      inserted_at TEXT
    )
    """

    execute """
    INSERT OR IGNORE INTO data_migrations (version, inserted_at)
    SELECT version, inserted_at FROM schema_migrations
    WHERE version IN (#{versions})
    """

    execute "DELETE FROM schema_migrations WHERE version IN (#{versions})"
  end

  # One-way: reversing would re-break the tracking split and cause the
  # data migrator to replay shipped backfills on the next run.
  def down, do: :ok
end
