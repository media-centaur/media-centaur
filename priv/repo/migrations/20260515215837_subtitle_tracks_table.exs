defmodule MediaCentarr.Repo.Migrations.SubtitleTracksTable do
  @moduledoc """
  Library Schema v2 Phase 1 Task 5 — moves subtitle tracks out of the
  `library_watched_files.subtitle_tracks` JSON column into the new
  `subtitles_tracks` table owned by the Subtitles context.

  **Reversibility caveat:** `down` re-creates the legacy column with an
  empty default and drops the new table. Detected subtitle tracks are
  lost on rollback — recovery requires re-running subtitle detection on
  the affected files. Acceptable in a no-deployed-users world; flagged
  here for any future rollback rehearsal.
  """
  use Ecto.Migration

  def up do
    create table(:subtitles_tracks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :watched_file_id,
          references(:library_watched_files, type: :binary_id, on_delete: :delete_all),
          null: false

      # :embedded | :sidecar — stored as a string; the Ecto.Enum cast lives
      # on the schema.
      add :kind, :string, null: false
      add :language, :string
      add :source, :string, null: false

      timestamps()
    end

    create index(:subtitles_tracks, [:watched_file_id])

    alter table(:library_watched_files) do
      remove :subtitle_tracks
    end
  end

  def down do
    alter table(:library_watched_files) do
      add :subtitle_tracks, {:array, :map}, default: []
    end

    drop table(:subtitles_tracks)
  end
end
