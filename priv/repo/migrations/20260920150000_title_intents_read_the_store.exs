defmodule MediaCentaur.Repo.Migrations.TitleIntentsReadTheStore do
  @moduledoc """
  A title intent stops embedding its title snapshot (campaign
  `tmdb-fetch-policy` Phase 3, ADR-071): the name, year, poster and
  overview the watchlist painted from `title_intents.title` are now read
  from the TMDB store, which `TMDB.CheckJob` fills for every listed title
  the store lacks.

  `down/0` restores the column empty: nothing refills it, since the
  snapshot is no longer written here.
  """
  use Ecto.Migration

  def up do
    alter table(:title_intents) do
      remove :title
    end
  end

  def down do
    alter table(:title_intents) do
      add :title, :map
    end
  end
end
