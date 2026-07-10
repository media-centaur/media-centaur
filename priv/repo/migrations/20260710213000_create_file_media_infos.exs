defmodule MediaCentaur.Repo.Migrations.CreateFileMediaInfos do
  use Ecto.Migration

  # Display-oriented technical metadata probed out of each media file
  # (ffprobe): container title tag, duration, video codec/resolution,
  # audio summary. Derived data per ADR-057 — recomputable from the file
  # at any time, so the table is purely additive and safely droppable.
  def change do
    create table(:library_file_media_infos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :file_presence_id,
          references(:library_file_presences, type: :binary_id, on_delete: :delete_all),
          null: false

      add :container_title, :string
      add :duration_seconds, :integer
      add :video_codec, :string
      add :width, :integer
      add :height, :integer
      add :audio_summary, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:library_file_media_infos, [:file_presence_id])
  end
end
