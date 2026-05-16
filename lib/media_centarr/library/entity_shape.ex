defmodule MediaCentarr.Library.EntityShape do
  @moduledoc """
  Normalizes type-specific records (Movie, TVSeries, MovieSeries, VideoObject) into
  a common map shape used by ProgressSummary, ResumeTarget, and LiveView templates.

  Also extracts watch progress records from preloaded associations so callers don't
  need to know the internal structure of each type.
  """

  @doc """
  Converts a type-specific record into a normalized map with all entity-level fields.

  Missing associations default to empty lists. Fields that don't exist on a given
  type (e.g. `duration_seconds` on TVSeries) return `nil` via `Map.get/3`.

  TMDB / IMDB ids are derived from the record's preloaded `:external_ids`
  association (Library Schema v2 Phase 1 Task 6); callers must preload it
  for `:imdb_id` to be populated.
  """
  def normalize(record, type) do
    external_ids = Map.get(record, :external_ids, [])

    %{
      id: record.id,
      type: type,
      name: record.name,
      description: record.description,
      date_published: record.date_published,
      content_url: Map.get(record, :content_url),
      url: record.url,
      genres: Map.get(record, :genres),
      duration_seconds: Map.get(record, :duration_seconds),
      director: Map.get(record, :director),
      content_rating: Map.get(record, :content_rating),
      number_of_seasons: Map.get(record, :number_of_seasons),
      aggregate_rating_value: Map.get(record, :aggregate_rating_value),
      vote_count: Map.get(record, :vote_count),
      tagline: Map.get(record, :tagline),
      original_language: Map.get(record, :original_language),
      studio: Map.get(record, :studio),
      country_code: Map.get(record, :country_code),
      network: Map.get(record, :network),
      status: Map.get(record, :status),
      cast: Map.get(record, :cast) || [],
      crew: Map.get(record, :crew) || [],
      imdb_id: extract_external_id(external_ids, "imdb"),
      collection: collection_from(record, type),
      images: Map.get(record, :images, []),
      external_ids: external_ids,
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

  defp extract_external_id(external_ids, source_str) when is_list(external_ids) do
    Enum.find_value(external_ids, fn
      %{source: ^source_str, external_id: value} -> value
      _ -> nil
    end)
  end

  defp extract_external_id(_, _), do: nil

  @doc """
  Extracts watch progress records from a type-specific struct's preloaded associations.

  Dispatches by type atom to dig into the correct nested structure:
  - `:tv_series` — walks seasons > episodes > watch_progress
  - `:movie_series` — walks movies > watch_progress
  - `:movie` / `:video_object` — wraps the single watch_progress record

  Each returned WatchProgress carries a synthesised `:playable_item`
  field with the owning container's `(container_type, container_id)`.
  The `has_one :watch_progress, through: [:playable_items, :watch_progress]`
  preload path doesn't materialise the `belongs_to :playable_item` back-ref
  on the loaded progress record, so this function plugs in just enough
  for downstream consumers (e.g. `EpisodeList.index_progress_by_key/1`)
  to key by container id.
  """
  def extract_progress(record, :tv_series), do: extract_episode_progress(record.seasons)
  def extract_progress(record, :movie_series), do: extract_movie_progress(record.movies)
  def extract_progress(record, :movie), do: wrap_progress(record.watch_progress, :movie, record.id)

  def extract_progress(record, :video_object),
    do: wrap_progress(record.watch_progress, :video_object, record.id)

  defp extract_episode_progress(seasons) when is_list(seasons) do
    for season <- seasons,
        episode <- season.episodes || [],
        progress = episode.watch_progress,
        not is_nil(progress),
        do: attach_container(progress, :episode, episode.id)
  end

  defp extract_episode_progress(_), do: []

  defp extract_movie_progress(movies) when is_list(movies) do
    for movie <- movies,
        progress = movie.watch_progress,
        not is_nil(progress),
        do: attach_container(progress, :movie, movie.id)
  end

  defp extract_movie_progress(_), do: []

  defp wrap_progress(nil, _container_type, _container_id), do: []

  defp wrap_progress(progress, container_type, container_id),
    do: [attach_container(progress, container_type, container_id)]

  # Plugs a synthesised `:playable_item` onto a WatchProgress so
  # downstream code can key by container id without an extra preload.
  defp attach_container(progress, container_type, container_id) do
    %{
      progress
      | playable_item: %{
          container_type: container_type,
          container_id: container_id
        }
    }
  end

  defp collection_from(%{movie_series: %{id: id, name: name}}, :movie), do: %{id: id, name: name}

  defp collection_from(_record, _type), do: nil
end
