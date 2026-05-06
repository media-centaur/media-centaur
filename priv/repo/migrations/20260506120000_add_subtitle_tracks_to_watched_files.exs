defmodule MediaCentarr.Repo.Migrations.AddSubtitleTracksToWatchedFiles do
  use Ecto.Migration

  def change do
    alter table(:library_watched_files) do
      add :subtitle_tracks, {:array, :map}, default: []
    end
  end
end
