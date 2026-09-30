defmodule MediaCentaur.Repo.Migrations.AcquisitionTargetsRelease do
  @moduledoc """
  A grabbing target stores the release chosen for it, so its grab never
  depends on the corpus keeping the candidate (campaign durable-work, G1).
  """
  use Ecto.Migration

  def change do
    alter table(:acquisition_targets) do
      add :release, :map
    end
  end
end
