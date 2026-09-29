defmodule MediaCentaur.Repo.Migrations.AwaitingFilesClaimedYear do
  @moduledoc """
  An awaiting file keeps the year its name claims, the evidence
  `EpisodeMapping.Models.YearMatch` places a yearly special by.
  """
  use Ecto.Migration

  def change do
    alter table(:episode_mapping_awaiting_files) do
      add :claimed_year, :integer
    end
  end
end
