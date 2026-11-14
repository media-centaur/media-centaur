defmodule MediaCentaur.Library.MovieOrder do
  @moduledoc """
  Shared helpers for walking a MovieSeries entity's child movies.
  Parallel to EpisodeOrder but for MovieSeries.

  Ordinals here are 1-based *walk positions* used by the playback
  resume chain and its display hints ("Play Movie 2") — they are not a
  storage key. `WatchProgress` is keyed by `(profile_id, playable_item_id)`
  (ADR-078), and the UI addresses movies by their container UUID.
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

  @doc "The order key of a collection movie: release date, then collection position."
  @spec order_key(map()) :: [String.t()]
  def order_key(movie) do
    position = Map.get(movie, :collection_position) || Map.get(movie, :position) || 0

    [
      (movie.date_published && Date.to_iso8601(movie.date_published)) || "",
      position |> Integer.to_string() |> String.pad_leading(5, "0")
    ]
  end

  @doc "The collection's ordered set: `%{id, key}` for every movie with a file, in story order."
  @spec ordered_items(map()) :: [%{id: Ecto.UUID.t(), key: [String.t()]}]
  def ordered_items(entity) do
    (entity.movies || [])
    |> sort_movies()
    |> Enum.filter(& &1.content_url)
    |> Enum.map(&%{id: &1.id, key: order_key(&1)})
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
  Count of movies with content_url.
  """
  def total_available(entity) do
    length(list_available(entity))
  end
end
