defmodule MediaCentarr.Repo.Migrations.AddNextAttemptAtToAcquisitionTargets do
  use Ecto.Migration

  # Denormalises the "when will we try again" signal off Oban's
  # scheduled_at onto the target row, so the read path (pursuit status,
  # row rendering, modal) can show "next attempt in 2h 15m" without
  # querying Oban per pursuit.
  #
  # Write-side: PursueTarget worker computes and persists this in the
  # same transaction it schedules the snooze; terminal-state changesets
  # null it.
  def change do
    alter table(:acquisition_targets) do
      add :next_attempt_at, :utc_datetime
    end
  end
end
