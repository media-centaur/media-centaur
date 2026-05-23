defmodule Mix.Tasks.Ecto.MigrateData do
  @shortdoc "Runs pending data migrations from priv/repo/data_migrations/"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Runs every pending data migration tracked in the `data_migrations` table.

      mix ecto.migrate_data

  Data migrations are distinct from schema migrations — see
  `MediaCentaur.DataMigrations` for the authoring contract. Production
  releases run this from `MediaCentaur.Release.migrate_data/0` after
  schema migrations and before the symlink flip; this Mix task is the
  dev-parity entry point.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    for repo <- Application.fetch_env!(:media_centaur, :ecto_repos) do
      MediaCentaur.DataMigrations.run!(repo)
    end
  end
end
