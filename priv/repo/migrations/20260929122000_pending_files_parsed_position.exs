defmodule MediaCentaur.Repo.Migrations.PendingFilesParsedPosition do
  @moduledoc """
  A review item's season and episode are what its name claims, never a
  decision: Review decides identity only, and a position is decided in
  episode mapping. The columns are named as claims, beside `parsed_title`
  and `parsed_year`.
  """
  use Ecto.Migration

  def change do
    rename table(:review_pending_files), :season_number, to: :parsed_season
    rename table(:review_pending_files), :episode_number, to: :parsed_episode
  end
end
