defmodule MediaCentarr.Repo.Migrations.SubtitleTracksTable do
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
