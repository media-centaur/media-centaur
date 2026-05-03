defmodule MediaCentarr.Library.PresentableQueries do
  @moduledoc """
  Composable Ecto query fragments that encode the "presentable" hoist rule
  for browse-style surfaces.

  ## The hoist rule

  TMDB collections (`MovieSeries`) are linked from `Movie.movie_series_id`
  whenever TMDB returns a `belongs_to_collection`. Browse surfaces should
  not render a collection container when only one of its movies is in the
  user's library — the user should see the movie directly, with the
  collection preserved as queryable metadata (the `movie_series` belongs_to
  association on the Movie).

  ## Three presentable kinds for movie-shaped rows

    * `standalone_movies/0` — `movie_series_id IS NULL`, present files only
    * `singleton_collection_movies/0` — sole present child of its
      `MovieSeries`; the row to surface in place of the collection container
    * `multi_child_movie_series/0` — `MovieSeries` with 2+ present children;
      the row to surface as a collection container

  Together they partition every Movie/MovieSeries the user sees at the top
  level. Each is a query fragment — callers compose `order_by`, `limit`, and
  `Repo.preload/2` per surface.

  All three exclude rows whose `WatchedFile`s do not have a corresponding
  `KnownFile` in `:present` state, matching the existing browse semantics.

  All queries name their primary binding `:item` so callers can compose with
  `from([m] in PresentableQueries.standalone_movies(), where: ...)` or use
  `parent_as(:item)` from a subquery.
  """
  import Ecto.Query

  alias MediaCentarr.Library.{Movie, MovieSeries}
  alias MediaCentarr.Watcher.KnownFile

  @doc """
  Standalone movies: `movie_series_id IS NULL`, with at least one present file.
  """
  def standalone_movies do
    from(m in Movie,
      as: :item,
      where: is_nil(m.movie_series_id),
      where: exists(present_files_subquery(:movie_id))
    )
  end

  @doc """
  Singleton-collection movies: a movie that is the sole present child of its
  `MovieSeries`. Use when the surface wants the child movie shown in place of
  a 1-movie collection container.
  """
  def singleton_collection_movies do
    from(m in Movie,
      as: :item,
      where: not is_nil(m.movie_series_id),
      where: exists(present_files_subquery(:movie_id)),
      where:
        fragment(
          """
          (SELECT COUNT(*)
             FROM library_movies AS m2
            WHERE m2.movie_series_id = ?
              AND EXISTS (
                SELECT 1
                  FROM library_watched_files AS wf
                  JOIN watcher_files AS kf ON kf.file_path = wf.file_path
                 WHERE wf.movie_id = m2.id AND kf.state = 'present'
              )
          ) = 1
          """,
          m.movie_series_id
        )
    )
  end

  @doc """
  Movie series with 2+ present children. Use when the surface wants a collection
  container row. (The 1-child case is delegated to `singleton_collection_movies/0`.)
  """
  def multi_child_movie_series do
    from(ms in MovieSeries,
      as: :item,
      where:
        fragment(
          """
          (SELECT COUNT(*)
             FROM library_movies AS m
            WHERE m.movie_series_id = ?
              AND EXISTS (
                SELECT 1
                  FROM library_watched_files AS wf
                  JOIN watcher_files AS kf ON kf.file_path = wf.file_path
                 WHERE wf.movie_id = m.id AND kf.state = 'present'
              )
          ) >= 2
          """,
          ms.id
        )
    )
  end

  defp present_files_subquery(fk_column) do
    from(wf in "library_watched_files",
      join: kf in KnownFile,
      on: kf.file_path == wf.file_path,
      where: field(wf, ^fk_column) == parent_as(:item).id and kf.state == :present,
      select: 1
    )
  end
end
