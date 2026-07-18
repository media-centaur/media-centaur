defmodule MediaCentaur.Library.MovieList do
  @moduledoc """
  Shared helpers for walking a MovieSeries entity's child movies.
  Parallel to EpisodeList but for MovieSeries.

  Uses 1-based ordinals as the storage key in WatchProgress:
  `season_number: 0, episode_number: ordinal`.
  """

  @doc "Sorts movies chronologically by date_published, then position as tiebreaker."
  def sort_movies(movies) when is_list(movies) do
    # Use ISO 8601 string for the date sort key — Erlang term ordering on
    # `%Date{}` structs sorts by map-key order (calendar → day → month →
    # year), which would mis-order entries from different months. The
    # canonical `"YYYY-MM-DD"` representation sorts lexicographically the
    # same as chronologically, and "" sorts before any populated date.
    Enum.sort_by(movies, fn movie ->
      # `sort_movies` is fed two shapes: full Movie structs (`:position`) and
      # the MovieSeries detail/resume projection maps from
      # `DetailItem.movie_entry_to_map/1` (`:collection_position`). Read either.
      position = Map.get(movie, :collection_position) || Map.get(movie, :position) || 0
      {(movie.date_published && Date.to_iso8601(movie.date_published)) || "", position}
    end)
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
