defmodule MediaCentarr.Repo.Migrations.RepointCollectionChildWatchedFiles do
  @moduledoc """
  Backfill: move `library_watched_files.movie_series_id` to `movie_id` for
  files that belong to a child movie of a collection.

  ## Why

  `Library.Inbound.link_file/2` previously used the top-level
  `event.entity_type` to set the WatchedFile FK. For a movie ingested as
  part of a collection, that entity_type is `:movie_series`, so the file
  was attached to the parent collection (`movie_series_id`) rather than
  the child Movie (`movie_id`).

  `PresentableQueries.multi_child_movie_series/0` and
  `singleton_collection_movies/0` count files via `wf.movie_id` on child
  Movies. With files misattached one level up, every collection was
  filtered out of the library view (and every singleton-collection child
  movie was hidden too).

  The companion fix in `Inbound.file_owner_for/2` prevents new
  misattachments; this migration repairs existing rows.

  ## Mapping

  For each misattached row, the correct `movie_id` is the child Movie
  whose `content_url` equals the WatchedFile's `file_path` AND whose
  `movie_series_id` matches the WatchedFile's misattached
  `movie_series_id`. That match is unambiguous: a Movie's
  `content_url` is the single canonical file path for that movie.

  Rows that don't match a child Movie are left untouched — manual
  inspection via the in-app library tools is the right next step rather
  than silent loss of data.

  Idempotent: the UPDATE has no effect on rows that already have
  `movie_id` set or no matching Movie.
  """

  use Ecto.Migration

  def up do
    # Historical: this row-repair belongs in priv/repo/data_migrations/ per
    # ADR-040. It shipped here before MC0015 enforced that discipline (the
    # dev-marks-done trap it caused is what motivated the check). Future
    # row-repairs go in data_migrations.
    execute("""
    UPDATE library_watched_files
       SET movie_id = (
             SELECT m.id
               FROM library_movies AS m
              WHERE m.movie_series_id = library_watched_files.movie_series_id
                AND m.content_url = library_watched_files.file_path
              LIMIT 1
           ),
           movie_series_id = NULL
     WHERE movie_id IS NULL
       AND movie_series_id IS NOT NULL
       AND EXISTS (
             SELECT 1
               FROM library_movies AS m
              WHERE m.movie_series_id = library_watched_files.movie_series_id
                AND m.content_url = library_watched_files.file_path
           )
    """)
  end

  def down do
    execute("""
    UPDATE library_watched_files
       SET movie_series_id = (
             SELECT m.movie_series_id
               FROM library_movies AS m
              WHERE m.id = library_watched_files.movie_id
                AND m.movie_series_id IS NOT NULL
              LIMIT 1
           ),
           movie_id = NULL
     WHERE movie_id IS NOT NULL
       AND EXISTS (
             SELECT 1
               FROM library_movies AS m
              WHERE m.id = library_watched_files.movie_id
                AND m.movie_series_id IS NOT NULL
                AND m.content_url = library_watched_files.file_path
           )
    """)
  end
end
