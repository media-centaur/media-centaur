defmodule MediaCentaur.Release do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Brings the database up to this code's version.

  `migrate/0` is the one operation. It starts each repo with a single
  connection and runs `upgrade/1` against it:

  1. When the database has migrations applied and a schema or data
     migration is pending, it takes a `SelfUpdate.DatabaseSnapshot`, so
     the database as it was before the update is kept. A snapshot that
     cannot be written stops the upgrade before anything migrates.
  2. Schema migrations.
  3. Data migrations — one-shot row backfills, tracked separately in the
     `data_migrations` table. See `MediaCentaur.DataMigrations` for
     authoring rules.

  It runs in two places, and nowhere needs a person to run it:

    * At every application start, as
      `MediaCentaur.Application.DatabaseUpgrade` — directly before the
      Repo, so before any process that reads the database. A process
      therefore never loads rows a pending migration is about to rewrite,
      whichever way the application was started.
    * From the installer, against the new release before `current` points
      at it, so a migration that fails leaves the running release in place:

          bin/media_centaur eval "MediaCentaur.Release.migrate()"

  `rollback/2` is the manual way back for a schema migration:

      bin/media_centaur eval "MediaCentaur.Release.rollback(MediaCentaur.Repo, 20240101000000)"

  `migrate/0` and `rollback/2` start the repo with one connection. With
  the migrator's default two, both connections switch a brand-new database
  to WAL at once; exqlite sets `journal_mode` before `busy_timeout`, so one
  of them fails at once with "database is locked" and reconnects —
  harmless, but the first install logs it as an error. SQLite's migration
  lock needs no second connection.
  """

  alias MediaCentaur.DataMigrations
  alias MediaCentaur.SelfUpdate.DatabaseSnapshot

  @app :media_centaur
  @migrator_opts [pool_size: 1]

  @doc "Starts each repo with one connection, runs `upgrade/1` against it and stops it."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &upgrade/1, @migrator_opts)
    end

    :ok
  end

  @doc """
  Brings the started `repo`'s database up to this code's version: the
  snapshot when one is due, then the schema migrations, then the data
  migrations. Does nothing when nothing is pending.
  """
  @spec upgrade(module()) :: :ok
  def upgrade(repo) do
    if snapshot_due?(Ecto.Migrator.migrations(repo), DataMigrations.pending?(repo)) do
      DatabaseSnapshot.take!(Keyword.fetch!(repo.config(), :database), version())
    end

    Ecto.Migrator.run(repo, :up, all: true)
    DataMigrations.run!(repo)
    :ok
  end

  @doc """
  Whether a database is copied before it is upgraded: it has at least one
  schema migration applied — a new database holds nothing to keep — and a
  schema or data migration is pending. `schema_statuses` is
  `Ecto.Migrator.migrations/1`'s list.
  """
  @spec snapshot_due?([{:up | :down, integer(), String.t()}], boolean()) :: boolean()
  def snapshot_due?(schema_statuses, data_pending?) do
    applied? = Enum.any?(schema_statuses, &match?({:up, _version, _name}, &1))
    schema_pending? = Enum.any?(schema_statuses, &match?({:down, _version, _name}, &1))

    applied? and (schema_pending? or data_pending?)
  end

  defp version, do: @app |> Application.spec(:vsn) |> to_string()

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version), @migrator_opts)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:logger)
    Application.load(@app)
  end
end
