defmodule MediaCentaur.DataMigrationsTest do
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

  alias MediaCentaur.DataMigrations

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

    test "directory contains the watchlist title-embed backfill" do
      files = DataMigrations.path() |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".exs"))
      assert "20260902120100_backfill_watchlist_title_embed.exs" in files
    end

    test "directory contains the show_watchlist settings-key rename" do
      files = DataMigrations.path() |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".exs"))
      assert "20260902150000_rename_show_watchlist_settings_key.exs" in files
    end
  end

  describe "with_data_migration_source/2" do
    # Regression net for the most damaging silent failure: the runner
    # tracking versions in `schema_migrations` instead of the dedicated
    # `data_migrations` table. The original implementation passed
    # `migration_source:` as an option to `Ecto.Migrator.run/4`, which
    # ecto_sql silently ignores — the versions table name is read from
    # *repo config* only (`SchemaMigration.get_repo_and_source/2`). A
    # source-literal pin missed that, so these tests assert the actual
    # mechanism: the repo config carries the override while the wrapped
    # function runs.
    test "overrides the repo's :migration_source during the call and restores it after" do
      refute MediaCentaur.Repo.config()[:migration_source]

      result =
        DataMigrations.with_data_migration_source(MediaCentaur.Repo, fn ->
          assert MediaCentaur.Repo.config()[:migration_source] == "data_migrations"
          :wrapped_result
        end)

      assert result == :wrapped_result
      refute MediaCentaur.Repo.config()[:migration_source]
    end

    test "restores the repo config even when the wrapped function raises" do
      assert_raise RuntimeError, "boom", fn ->
        DataMigrations.with_data_migration_source(MediaCentaur.Repo, fn ->
          raise "boom"
        end)
      end

      refute MediaCentaur.Repo.config()[:migration_source]
    end
  end

  describe "run!/1" do
    test "runs in the :up direction — data migrations are forward-only" do
      source = File.read!("lib/media_centaur/data_migrations.ex")
      assert source =~ ~r/Ecto\.Migrator\.run\([^,]+,[^,]+,\s*:up\s*,/
    end
  end
end
