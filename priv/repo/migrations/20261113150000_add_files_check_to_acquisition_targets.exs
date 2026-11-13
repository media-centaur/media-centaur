defmodule MediaCentaur.Repo.Migrations.AddFilesCheckToAcquisitionTargets do
  @moduledoc """
  The one look at a torrent's file list: when it was taken, and what was
  wrong with it, if anything (`Acquisition.DeliveredFiles`).
  """
  use Ecto.Migration

  def change do
    alter table(:acquisition_targets) do
      add :files_checked_at, :utc_datetime
      add :files_problem, :text
    end
  end
end
