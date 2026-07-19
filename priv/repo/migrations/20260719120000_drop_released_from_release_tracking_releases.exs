defmodule MediaCentaur.Repo.Migrations.DropReleasedFromReleaseTrackingReleases do
  use Ecto.Migration

  # `released` was a stored boolean that is exactly
  # `air_date != nil and air_date <= today` — materialised at insert time and
  # re-freshened by a midnight sweep. That made it stale across midnight (the
  # class of bug behind phantom "Season announced" states). It is now derived
  # from `air_date` on read (see `Release.released?/2`), so the column is dead.
  #
  # Reversible: `down/0` re-adds the column with the historical default. A
  # rebuild of any item's releases (the app does this on every refresh) would
  # re-materialise correct values, but the sweep no longer exists — the column
  # would simply stay at its default until then. Derivation is the source of
  # truth now.
  def up do
    alter table(:release_tracking_releases) do
      remove :released
    end
  end

  def down do
    alter table(:release_tracking_releases) do
      add :released, :boolean, default: false
    end
  end
end
