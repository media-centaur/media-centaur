defmodule MediaCentarr.Release do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Release tasks for running migrations from a deployed release.

      bin/media_centarr eval "MediaCentarr.Release.migrate()"
      bin/media_centarr eval "MediaCentarr.Release.migrate_data()"
      bin/media_centarr eval "MediaCentarr.Release.rollback(MediaCentarr.Repo, 20240101000000)"

  Boot order on a deploy:

  1. `migrate/0` — schema migrations (fast, atomic, blocks app start).
  2. `migrate_data/0` — one-shot data backfills against the new schema.
     Tracked separately in the `data_migrations` table.

  See `MediaCentarr.DataMigrations` for authoring rules.
  """

  @app :media_centarr

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Runs every pending data migration. Idempotent across deploys — the
  `data_migrations` table tracks which versions have already applied.
  """
  def migrate_data do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn started_repo ->
          MediaCentarr.DataMigrations.run!(started_repo)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:logger)
    Application.load(@app)
  end
end
