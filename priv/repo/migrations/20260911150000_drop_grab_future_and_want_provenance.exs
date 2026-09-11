defmodule MediaCentaur.Repo.Migrations.DropGrabFutureAndWantProvenance do
  @moduledoc """
  Drops the two columns behind the download-side tracking handoffs that
  left with `Acquisition.TrackingHandoffs` (campaign
  `watchlist-single-entry-point`, Phase 1):

  * `acquisition_plans.grab_future` — the "Also grab future episodes"
    opt-in, which raised the title to Grab when the plan's pursuit
    completed;
  * `release_tracking_wants.provenance` — `calendar` or `gap`, where
    `gap` marked a want opened by "Track these" on a plan's missing units.

  Release tracking is enabled on the watchlist and nowhere else
  ([ADR-066]): a download never moves a rung, so nothing reads either
  column any more. Going up loses nothing a person would miss — a plan's
  `grab_future` flag was a promise about a future rung change that no
  longer happens, and a gap want stays a want; only the label of where it
  came from goes. Down re-adds both columns at their defaults, so a former
  gap want reads as `calendar` after a rollback.

  [ADR-066]: `decisions/architecture/2026-09-07-066-one-ladder-per-title.md`
  """

  use Ecto.Migration

  def up do
    alter table(:acquisition_plans) do
      remove :grab_future
    end

    alter table(:release_tracking_wants) do
      remove :provenance
    end
  end

  def down do
    alter table(:acquisition_plans) do
      add :grab_future, :boolean, null: false, default: false
    end

    alter table(:release_tracking_wants) do
      add :provenance, :string, null: false, default: "calendar"
    end
  end
end
