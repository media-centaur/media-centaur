defmodule MediaCentarr.Repo.Migrations.DropGrabExcludedReleaseGuids do
  use Ecto.Migration

  # The pursuit aggregate's `tried_release_guids` array is the single
  # source of truth for "releases we've already attempted for this goal."
  # `acquisition_grabs.excluded_release_guids` was read by SearchAndGrab
  # but never written by any production code path — this migration drops
  # the redundant column and `SearchAndGrab` now reads from the linked
  # pursuit instead.
  def change do
    alter table(:acquisition_grabs) do
      remove :excluded_release_guids, {:array, :string}, default: []
    end
  end
end
