defmodule MediaCentarr.Repo.Migrations.ExtendGrabsWithOrigin do
  use Ecto.Migration

  def change do
    alter table(:acquisition_grabs) do
      # "auto" — system-initiated from a release-tracker {:release_ready, ...}
      # broadcast. "manual" — user-submitted from the Downloads page search form.
      # Stored as text rather than enum to keep schema-level state churn minimal
      # and to mirror the existing `status` column's string-typed style.
      add :origin, :string, default: "auto", null: false

      # The Prowlarr indexer-result GUID we used to grab. For manual grabs
      # we also stash this in `tmdb_id` (with `tmdb_type = "manual"`) so the
      # existing unique-by-key idempotency works without making `tmdb_id`
      # nullable — that change would require an SQLite table-recreate dance
      # for no real benefit. This column is the diagnostic surface and the
      # hook for a future "re-submit this exact release" action.
      add :prowlarr_guid, :string

      # The query string the user typed when this row was a manual grab.
      # Pure UX — surfaces "where did this row come from?" in the activity
      # list. NULL for auto-grabs.
      add :manual_query, :string
    end
  end
end
