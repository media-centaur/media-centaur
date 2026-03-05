defmodule MediaCentaur.Release do
  @moduledoc """
  Release tasks for running migrations from a deployed release.

      bin/media_centaur eval "MediaCentaur.Release.migrate()"
      bin/media_centaur eval "MediaCentaur.Release.rollback(MediaCentaur.Repo, 20240101000000)"
  """

  @app :media_centaur

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
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
