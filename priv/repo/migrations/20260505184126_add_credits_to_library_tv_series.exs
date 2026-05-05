defmodule MediaCentarr.Repo.Migrations.AddCreditsToLibraryTvSeries do
  @moduledoc """
  Adds `cast`, `crew`, and `imdb_id` columns to `library_tv_series` to
  power the More info detail panel for TV series — Created by row,
  aggregate cast grid, and IMDb external link.

  Mirrors the movie credit fields (`add_cast_to_library_movies`,
  `add_crew_and_imdb_id_to_movies`). No backfill — the user-driven
  refresh path is `Maintenance.refresh_series_credits/0`.
  """
  use Ecto.Migration

  def change do
    alter table(:library_tv_series) do
      add :cast, :map
      add :crew, :map
      add :imdb_id, :string
    end
  end
end
