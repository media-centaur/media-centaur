defmodule MediaCentaur.Library.EntityShape do
  @moduledoc """
  Normalizes type-specific records (Movie, TVSeries, MovieSeries, VideoObject) into
  a common map shape used by ProgressSummary, ResumeTarget, and LiveView templates.

  Also extracts watch progress records from preloaded associations so callers don't
  need to know the internal structure of each type.
  """

  @doc """
  Converts a type-specific record into a normalized map with all entity-level fields.

  Missing associations default to empty lists. Fields that don't exist on a given
  type (e.g. `duration` on TVSeries) return `nil` via `Map.get/3`.
  """
  def normalize(record, type) do
    %{
      id: record.id,
      type: type,
      name: record.name,
      description: record.description,
      date_published: record.date_published,
      content_url: Map.get(record, :content_url),
      url: record.url,
      genres: Map.get(record, :genres),
      duration: Map.get(record, :duration),
      director: Map.get(record, :director),
      content_rating: Map.get(record, :content_rating),
      number_of_seasons: Map.get(record, :number_of_seasons),
      aggregate_rating_value: Map.get(record, :aggregate_rating_value),
      images: Map.get(record, :images, []),
      external_ids: Map.get(record, :external_ids, []),
      extras: Map.get(record, :extras, []),
      seasons: Map.get(record, :seasons, []),
      movies: Map.get(record, :movies, []),
      watched_files: Map.get(record, :watched_files, []),
      watch_progress: [],
      extra_progress: [],
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  @doc """
  Extracts watch progress records from a type-specific struct's preloaded associations.

  Dispatches by type atom to dig into the correct nested structure:
  - `:tv_series` — walks seasons > episodes > watch_progress
  - `:movie_series` — walks movies > watch_progress
  - `:movie` / `:video_object` — wraps the single watch_progress record
  """
  def extract_progress(record, :tv_series), do: extract_episode_progress(record.seasons)
  def extract_progress(record, :movie_series), do: extract_movie_progress(record.movies)
  def extract_progress(record, :movie), do: wrap_progress(record.watch_progress)
  def extract_progress(record, :video_object), do: wrap_progress(record.watch_progress)

  defp extract_episode_progress(seasons) when is_list(seasons) do
    for season <- seasons,
        episode <- season.episodes || [],
        progress = episode.watch_progress,
        not is_nil(progress),
        do: progress
  end

  defp extract_episode_progress(_), do: []

  defp extract_movie_progress(movies) when is_list(movies) do
    for movie <- movies,
        progress = movie.watch_progress,
        not is_nil(progress),
        do: progress
  end

  defp extract_movie_progress(_), do: []

  defp wrap_progress(nil), do: []
  defp wrap_progress(progress), do: [progress]
end
