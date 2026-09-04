defmodule MediaCentaur.Library.EntityShape do
  @moduledoc """
  Adapts a preloaded type-specific container record (`Movie`, `TVSeries`,
  `MovieSeries`, `VideoObject`) into a `MediaCentaur.Library.EntityView` —
  the record-sourced counterpart of `Views.DetailItem.to_entity_view/1`.
  Used where the database, not the projection, is the source: playback
  resolution (`Playback.Resolver`, `NextEpisode`, `SessionRecovery`) and
  the Browse projection's rebuild (`Library.Browser`).

  `MediaCentaur.Library.PlayableItem` is the write-side leaf identity that
  files and progress key against; this module operates one layer up, at
  the container the user sees.

  ## Companion helpers (`extract_progress/2`, `attach_container/3`)

  `extract_progress/2` walks a container's preloaded associations and
  returns the `WatchProgress` rows attached to each leaf, each carrying
  a synthesised `:playable_item` field with the leaf's `(container_type,
  container_id)`. Downstream consumers
  (`MediaCentaur.Library.EpisodeList.index_progress_by_key/1`) key
  progress by container id without an extra preload of the
  `belongs_to :playable_item` back-ref.
  """

  alias MediaCentaur.Library.EntityView

  @doc """
  The `EntityView` of a preloaded container record.

  Missing associations default to empty lists. Fields that don't exist on
  a given type (e.g. `duration_seconds` on TVSeries) are `nil`. TMDB /
  IMDB ids come from the preloaded `:external_ids` association; callers
  must preload it for `:imdb_id` / `:tmdb_id` to be populated.
  """
  @spec to_entity_view(struct(), EntityView.kind()) :: EntityView.t()
  def to_entity_view(record, type) do
    external_ids = Map.get(record, :external_ids, [])

    struct!(EntityView,
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
      tmdb_id: extract_external_id(external_ids, "tmdb"),
      collection: collection_from(record, type),
      images: effective_images(record, type),
      external_ids: external_ids,
      extras: Map.get(record, :extras, []),
      seasons: Map.get(record, :seasons, []),
      movies: Map.get(record, :movies, []),
      watched_files: Map.get(record, :watched_files, []),
      subtitle_tracks: [],
      watch_progress: [],
      extra_progress: [],
      inserted_at: record.inserted_at,
      updated_at: record.updated_at,
      track_override: nil
    )
  end

  # A collection (MovieSeries) shows blank when TMDB has no collection-level
  # poster/backdrop. Borrow a constituent movie's art so the browse card
  # never renders empty. Other types use their own images verbatim. Child
  # images are preloaded by `Library.Browser`'s movie_series preload chain;
  # when they aren't (movies not loaded), the borrow degrades to own-only.
  defp effective_images(record, :movie_series) do
    MediaCentaur.Library.CollectionArtwork.effective_images(
      own_images(record),
      fallback_images_from_movies(Map.get(record, :movies))
    )
  end

  defp effective_images(record, _type), do: own_images(record)

  defp own_images(record) do
    case Map.get(record, :images) do
      images when is_list(images) -> images
      _ -> []
    end
  end

  defp fallback_images_from_movies(movies) when is_list(movies) do
    movies
    |> Enum.sort_by(&(Map.get(&1, :position) || 0))
    |> Enum.flat_map(fn movie ->
      case Map.get(movie, :images) do
        images when is_list(images) -> images
        _ -> []
      end
    end)
  end

  defp fallback_images_from_movies(_), do: []

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
