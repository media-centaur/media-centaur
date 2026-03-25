defmodule MediaCentaur.Playback.MovieList do
  @moduledoc """
  Shared helpers for walking a MovieSeries entity's child movies.
  Parallel to EpisodeList but for MovieSeries.

  Uses 1-based ordinals as the storage key in WatchProgress:
  `season_number: 0, episode_number: ordinal`.
  """

  @doc "Sorts movies chronologically by date_published, then position as tiebreaker."
  def sort_movies(movies) when is_list(movies) do
    Enum.sort_by(movies, fn movie -> {movie.date_published || "", movie.position || 0} end)
  end

  def sort_movies(_), do: []

  @doc """
  Returns a flat list of `{ordinal, movie_id, content_url}` tuples
  for child movies that have a content_url, sorted chronologically.
  Ordinals are 1-based.
  """
  def list_available(entity) do
    (entity.movies || [])
    |> sort_movies()
    |> Enum.filter(& &1.content_url)
    |> Enum.with_index(1)
    |> Enum.map(fn {movie, ordinal} -> {ordinal, movie.id, movie.content_url} end)
  end

  @doc """
  Indexes progress records by ordinal (episode_number) for records
  with `season_number == 0`.
  """
  def index_progress_by_ordinal(progress_records) do
    progress_records
    |> Enum.filter(&(&1.season_number == 0))
    |> Map.new(fn record -> {record.episode_number, record} end)
  end

  @doc """
  Finds the `{ordinal, movie_id, movie_name}` for a movie matching a content_url.

  Returns the tuple or `nil`.
  """
  def find_by_content_url(entity, content_url) do
    entity
    |> list_available()
    |> Enum.find_value(fn {ordinal, movie_id, url} ->
      if url == content_url do
        movie = Enum.find(entity.movies || [], &(&1.id == movie_id))
        {ordinal, movie_id, movie && movie.name}
      end
    end)
  end

  @doc """
  Finds `{movie_id, movie_name}` for a given ordinal.

  Returns the tuple or `nil`.
  """
  def find_movie_by_ordinal(entity, ordinal) do
    case Enum.find(list_available(entity), fn {ord, _id, _url} -> ord == ordinal end) do
      {_ordinal, movie_id, _url} ->
        movie = Enum.find(entity.movies || [], &(&1.id == movie_id))
        {movie_id, movie && movie.name}

      nil ->
        nil
    end
  end

  @doc """
  Count of movies with content_url.
  """
  def total_available(entity) do
    length(list_available(entity))
  end
end
