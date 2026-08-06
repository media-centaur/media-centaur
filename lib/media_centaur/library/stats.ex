defmodule MediaCentaur.Library.Stats do
  @moduledoc """
  Library-wide counts for the Status page's operational dashboard.

  The one rule worth stating: a `Movie` belonging to a `MovieSeries` is
  part of a collection, not a standalone title, so it is excluded from
  the `:movie` count. That distinction is the library's own and lives
  here rather than in the caller.
  """

  import Ecto.Query

  alias MediaCentaur.Library.{
    Episode,
    Image,
    Movie,
    MovieSeries,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  alias MediaCentaur.Repo

  @doc """
  Library-wide entity, episode, file and image counts for the Status page's
  operational dashboard.

  A `Movie` belonging to a `MovieSeries` is part of a collection, not a
  standalone title, so it is excluded from the `:movie` count. That
  distinction is the library's own rule and lives here, not in the caller.
  """
  @spec all() :: %{
          episodes: non_neg_integer(),
          files: non_neg_integer(),
          images: non_neg_integer(),
          by_type: %{
            movie: non_neg_integer(),
            tv_series: non_neg_integer(),
            movie_series: non_neg_integer(),
            video_object: non_neg_integer()
          }
        }
  def all do
    %{
      episodes: count_rows(Episode),
      files: count_rows(WatchedFile),
      images: count_rows(Image),
      by_type: %{
        movie: Repo.one(from(m in Movie, where: is_nil(m.movie_series_id), select: count(m.id))),
        tv_series: count_rows(TVSeries),
        movie_series: count_rows(MovieSeries),
        video_object: count_rows(VideoObject)
      }
    }
  end

  defp count_rows(schema), do: Repo.one(from(record in schema, select: count(record.id)))
end
