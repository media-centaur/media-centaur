defmodule MediaCentarr.DataMigrationsTest do
  # `Ecto.Migrator.run/4` requires two DB connections (one to lock the
  # tracking table, one to run migrations) which is incompatible with
  # `Ecto.Adapters.SQL.Sandbox`'s single-connection model. So instead of
  # running the migrator end-to-end here, we pin the runner's contract
  # via structural checks: the path resolves correctly, the migration
  # file is discoverable, and the source uses `migration_source:
  # "data_migrations"` (not the schema-migrations stream).
  #
  # End-to-end verification happens via `mix ecto.migrate_data` against
  # a real DB — the dev workflow exercises the same code path that
  # production uses.
  use ExUnit.Case, async: true

  alias MediaCentarr.DataMigrations

  describe "path/0" do
    test "resolves to the priv/repo/data_migrations directory inside the app" do
      path = DataMigrations.path()
      assert String.ends_with?(path, "priv/repo/data_migrations")
      assert File.dir?(path)
    end

    test "directory contains the orphaned-pursuits backfill migration" do
      files =
        DataMigrations.path()
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".exs"))

      assert "20260509120000_backfill_orphaned_pursuits.exs" in files
    end
  end

  describe "run!/1" do
    test "uses the dedicated 'data_migrations' tracking table, not 'schema_migrations'" do
      # Regression net for the most damaging silent failure: the runner
      # accidentally pointed at `schema_migrations` would corrupt the
      # schema-migrations tracker and double-apply schema migrations.
      # Pin the literal in source.
      source = File.read!("lib/media_centarr/data_migrations.ex")
      assert source =~ ~s(migration_source: "data_migrations")
      refute source =~ ~s(migration_source: "schema_migrations")
    end

    test "runs in the :up direction — data migrations are forward-only" do
      source = File.read!("lib/media_centarr/data_migrations.ex")
      assert source =~ ~r/Ecto\.Migrator\.run\([^,]+,[^,]+,\s*:up\s*,/
    end
  end
end
