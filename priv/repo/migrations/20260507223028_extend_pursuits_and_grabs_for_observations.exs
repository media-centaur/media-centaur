defmodule MediaCentarr.Repo.Migrations.ExtendPursuitsAndGrabsForObservations do
  use Ecto.Migration

  def change do
    alter table(:acquisition_pursuits) do
      add :stall_first_seen_at, :utc_datetime
      add :zero_seeders_first_seen_at, :utc_datetime
    end

    alter table(:acquisition_grabs) do
      add :release_title, :string
    end
  end
end
