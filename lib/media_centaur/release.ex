defmodule MediaCentaur.Release do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Release tasks for running migrations from a deployed release.

      bin/media_centaur eval "MediaCentaur.Release.migrate()"
      bin/media_centaur eval "MediaCentaur.Release.migrate_data()"
      bin/media_centaur eval "MediaCentaur.Release.rollback(MediaCentaur.Repo, 20240101000000)"

  Boot order on a deploy:

  1. `migrate/0` — schema migrations (fast, atomic, blocks app start).
     When the database already existed and a schema or data migration is
     pending, it first takes a `SelfUpdate.DatabaseSnapshot`, so the
     database as it was before the update is kept. A snapshot that
     cannot be written stops the update before anything migrates.
  2. `migrate_data/0` — one-shot data backfills against the new schema.
     Tracked separately in the `data_migrations` table.

  See `MediaCentaur.DataMigrations` for authoring rules.

  Every task starts the repo with one connection. With the migrator's
  default two, both connections switch a brand-new database to WAL at
  once; exqlite sets `journal_mode` before `busy_timeout`, so one of them
  fails at once with "database is locked" and reconnects — harmless, but
  the first install logs it as an error. SQLite's migration lock needs no
  second connection.
  """

  alias MediaCentaur.SelfUpdate.DatabaseSnapshot

  @app :media_centaur
  @migrator_opts [pool_size: 1]

  def migrate do
    load_app()

    for repo <- repos() do
      database = Keyword.fetch!(repo.config(), :database)
      existed? = File.exists?(database)

      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn started_repo ->
            if existed? and pending?(started_repo), do: DatabaseSnapshot.take!(database, version())
            Ecto.Migrator.run(started_repo, :up, all: true)
          end,
          @migrator_opts
        )
    end
  end

  defp pending?(repo) do
    Enum.any?(Ecto.Migrator.migrations(repo), &match?({:down, _version, _name}, &1)) or
      MediaCentaur.DataMigrations.pending?(repo)
  end

  defp version, do: @app |> Application.spec(:vsn) |> to_string()

  @doc """
  Runs every pending data migration. Idempotent across deploys — the
  `data_migrations` table tracks which versions have already applied.
  """
  def migrate_data do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn started_repo -> MediaCentaur.DataMigrations.run!(started_repo) end,
          @migrator_opts
        )
    end
  end

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
