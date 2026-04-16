defmodule MediaCentarr.Repo.Migrations.RenameTablesWithContextPrefix do
  use Ecto.Migration

  def change do
    # Library context
    rename table(:entities), to: table(:library_entities)
    rename table(:seasons), to: table(:library_seasons)
    rename table(:episodes), to: table(:library_episodes)
    rename table(:movies), to: table(:library_movies)
    rename table(:extras), to: table(:library_extras)
    rename table(:images), to: table(:library_images)
    rename table(:identifiers), to: table(:library_identifiers)
    rename table(:watched_files), to: table(:library_watched_files)
    rename table(:watch_progress), to: table(:library_watch_progress)
    rename table(:extra_progress), to: table(:library_extra_progress)
    rename table(:change_entries), to: table(:library_change_entries)

    # Settings context
    rename table(:settings), to: table(:settings_entries)
  end
end
