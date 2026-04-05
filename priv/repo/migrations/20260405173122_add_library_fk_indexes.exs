defmodule MediaCentaur.Repo.Migrations.AddLibraryFkIndexes do
  use Ecto.Migration

  # Adds single-column indexes on the type-specific FK columns across the
  # library_* tables. These foreign keys are used by lookups in the
  # LibraryLive event handlers (notably toggle_watched), by
  # Library.get_watch_progress_by_fk/2, and by the various find_or_create
  # functions — none of which currently hit an index on these columns.
  #
  # library_images is intentionally skipped: its FK columns are already
  # covered by composite unique indexes on (fk_id, role), which SQLite
  # uses as a leading-column index for single-column lookups.
  def change do
    # library_watch_progress — the audit's primary target.
    # Used by toggle_watched -> get_watch_progress_by_fk in a hot path.
    create index(:library_watch_progress, [:movie_id])
    create index(:library_watch_progress, [:episode_id])
    create index(:library_watch_progress, [:video_object_id])

    # library_external_ids (renamed from library_identifiers in 20260403163710).
    # Used by the pipeline when looking up existing entities by TMDB/IMDB ID.
    create index(:library_external_ids, [:movie_id])
    create index(:library_external_ids, [:tv_series_id])
    create index(:library_external_ids, [:movie_series_id])
    create index(:library_external_ids, [:video_object_id])

    # library_watched_files — used by the pipeline dedup checks and by
    # library_live "files linked to this entity" queries.
    create index(:library_watched_files, [:movie_id])
    create index(:library_watched_files, [:tv_series_id])
    create index(:library_watched_files, [:movie_series_id])
    create index(:library_watched_files, [:video_object_id])

    # library_extras — used when loading a parent entity's extras list.
    create index(:library_extras, [:movie_id])
    create index(:library_extras, [:tv_series_id])
    create index(:library_extras, [:movie_series_id])

    # library_movies — the FK from child movies to their parent MovieSeries.
    # Used when loading all movies in a collection.
    create index(:library_movies, [:movie_series_id])
  end
end
