defmodule MediaCentarr.Repo.Migrations.AddLastQueueStateToPursuits do
  use Ecto.Migration

  def change do
    alter table(:acquisition_pursuits) do
      add :last_queue_state, :string
      add :last_queue_health, :string
    end
  end
end
