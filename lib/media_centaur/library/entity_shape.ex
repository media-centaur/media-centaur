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
  the container the user sees. Progress is not read here: a title's
  progress comes from `MediaCentaur.Library.ProgressRecords.list_for_container/3`.
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

  defp collection_from(%{movie_series: %{id: id, name: name}}, :movie), do: %{id: id, name: name}

  defp collection_from(_record, _type), do: nil
end
