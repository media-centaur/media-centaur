defmodule MediaCentarr.Repo.Migrations.AddInLibraryAtToReleases do
  use Ecto.Migration

  def change do
    alter table(:release_tracking_releases) do
      # Stamped by `mark_in_library_releases/1` on the first transition
      # from `in_library: false` to `true`. Powers the 24-hour linger
      # window that keeps recently-completed releases visible on the
      # "Now Available" section so users see the success state instead
      # of the row vanishing the moment the watcher imports the file.
      #
      # NULL for any row that was already `in_library: true` before this
      # migration ran — those rows won't appear in the linger window after
      # deploy (correct: avoids a flood of phantom "completed" rows).
      add :in_library_at, :utc_datetime
    end
  end
end
