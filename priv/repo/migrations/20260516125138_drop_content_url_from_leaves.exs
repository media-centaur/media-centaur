defmodule MediaCentarr.Repo.Migrations.DropContentUrlFromLeaves do
  use Ecto.Migration

  # Library Schema v2 Phase 2 Task I.
  #
  # After Phase 2 Task B, `library_watched_files.file_path` is the single
  # source of truth for the on-disk path of a playable thing. The
  # `content_url` columns on `library_movies`, `library_episodes`, and
  # `library_video_objects` had been a denormalized cache of that same
  # path — drop them outright so writes can't drift.
  #
  # Extras keep their `content_url` (see `library_extras` and
  # `library_extra_files`): Extras are not PlayableItems and Phase 1
  # preserved the column as the canonical playable path for bonus
  # features. Images retain `content_url` too — different schema, refers
  # to the artwork file's relative path.
  def up do
    alter table(:library_movies) do
      remove :content_url
    end

    alter table(:library_episodes) do
      remove :content_url
    end

    alter table(:library_video_objects) do
      remove :content_url
    end
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "drop_content_url_from_leaves is not reversible — the path of record now lives on " <>
          "library_watched_files.file_path via PlayableItem; restoring the columns would " <>
          "require backfilling from WatchedFile joins, which the schema no longer expresses " <>
          "deterministically (a leaf may have multiple WatchedFiles)."
  end
end
