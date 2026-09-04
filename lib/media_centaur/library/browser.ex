defmodule MediaCentaur.Library.Browser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries.
  """
  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.{
    EntityShape,
    Movie,
    MovieSeries,
    PresentableQueries,
    TVSeries,
    VideoObject
  }

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EpisodeList, MovieList, ProgressSummary}
  alias MediaCentaur.Repo

  # Leaf preload chain for materialising the virtual `Episode.content_url` /
  # `Movie.content_url` / `VideoObject.content_url` field (Library Schema
  # v2 Phase 2 Task I). `Library.ContentUrls.populate/1` walks
  # `playable_items.watched_files` and stamps the file path on the leaf
  # struct — the catalog grid keeps reading `entity.content_url` /
  # `episode.content_url` without code changes.
  @leaf_file_path_preload [playable_items: :watched_files]

  @standalone_movie_preloads [:images, :external_ids, :watched_files, :watch_progress] ++
                               @leaf_file_path_preload
  @hoisted_movie_preloads [
                            :images,
                            :external_ids,
                            :watched_files,
                            :watch_progress,
                            :movie_series
                          ] ++ @leaf_file_path_preload
  @tv_series_preloads [
    :images,
    :external_ids,
    :watched_files,
    seasons: [episodes: [:images, :watch_progress] ++ @leaf_file_path_preload]
  ]
  @movie_series_preloads [
    :images,
    :external_ids,
    :watched_files,
    movies: [:images, :watch_progress] ++ @leaf_file_path_preload
  ]
  @video_object_preloads [:images, :external_ids, :watched_files, :watch_progress] ++
                           @leaf_file_path_preload

  @doc """
  Loads all library entries from the type-specific tables
  (Movie, TVSeries, MovieSeries, VideoObject), computes progress summaries.

  Returns a list of `%{entity: entity, progress: summary, progress_records: records}`.

  ## Options

    * `:sort` — one of `:recent` (default) or `:alpha`.
      * `:recent` — `inserted_at desc` (Library Schema v2 Phase 3.1). This
        is the canonical Browse projection order — "what did I just add?".
      * `:alpha` — case-insensitive sort by `entity.name`. Retained for
        consumers that still want alphabetical ordering directly off the
        Browser layer.
  """
  def fetch_all_typed_entries(opts \\ []) do
    standalone_movies = fetch_standalone_movies()
    hoisted_movies = fetch_hoisted_movies()
    tv_series = fetch_all_tv_series()
    movie_series = fetch_all_movie_series()
    video_objects = fetch_all_video_objects()

    entries =
      standalone_movies ++ hoisted_movies ++ tv_series ++ movie_series ++ video_objects

    Log.info(
      :library,
      "loaded #{length(entries)} typed entries for browser " <>
        "(#{length(standalone_movies)} standalone movies, " <>
        "#{length(hoisted_movies)} hoisted-collection movies, " <>
        "#{length(tv_series)} tv, " <>
        "#{length(movie_series)} multi-child movie series, " <>
        "#{length(video_objects)} video objects)"
    )

    entries
    |> Enum.map(&build_typed_entry/1)
    |> apply_sort(Keyword.get(opts, :sort, :recent))
  end

  @epoch_inserted_at ~U[2000-01-01 00:00:00Z]

  defp apply_sort(entries, :recent) do
    # Module-aware sort: Erlang term-order on `%DateTime{}` is not
    # chronological; `{:desc, DateTime}` forces `DateTime.compare/2`.
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.inserted_at || @epoch_inserted_at end,
      {:desc, DateTime}
    )
  end

  # --- Type-Specific Fetchers (all) ---
  #
  # All fetchers use `Repo.all |> Repo.preload(...)`, which issues one query
  # per (association, parent type) pair via an `IN` clause. The total cost is
  # a bounded constant (~29 queries) that does NOT scale with row count. This
  # is the standard Ecto preload pattern, not N+1, and is enforced as a
  # regression by `test/media_centaur/library_browser_test.exs` — see the
  # "query count (N+1 regression guard)" describe block.

  defp fetch_standalone_movies do
    PresentableQueries.standalone_movies()
    |> Repo.all()
    |> Repo.preload(@standalone_movie_preloads)
    |> Enum.map(&Library.ContentUrls.populate/1)
  end

  defp fetch_hoisted_movies do
    PresentableQueries.singleton_collection_movies()
    |> Repo.all()
    |> Repo.preload(@hoisted_movie_preloads)
    |> Enum.map(&Library.ContentUrls.populate/1)
  end

  defp fetch_all_tv_series do
    from(t in TVSeries,
      as: :item,
      where: exists(PresentableQueries.tv_series_present_file_subquery())
    )
    |> Repo.all()
    |> Repo.preload(@tv_series_preloads)
    |> Enum.map(&Library.ContentUrls.populate/1)
  end

  defp fetch_all_movie_series do
    PresentableQueries.multi_child_movie_series()
    |> Repo.all()
    |> Repo.preload(@movie_series_preloads)
    |> Enum.map(&Library.ContentUrls.populate/1)
  end

  defp fetch_all_video_objects do
    from(v in VideoObject,
      as: :item,
      where: exists(PresentableQueries.video_object_present_file_subquery())
    )
    |> Repo.all()
    |> Repo.preload(@video_object_preloads)
    |> Enum.map(&Library.ContentUrls.populate/1)
  end

  defp build_typed_entry(%Movie{} = movie) do
    build_entry_for(movie, :movie)
  end

  defp build_typed_entry(%TVSeries{} = series) do
    build_entry_for(series, :tv_series)
  end

  defp build_typed_entry(%MovieSeries{} = series) do
    build_entry_for(series, :movie_series)
  end

  defp build_typed_entry(%VideoObject{} = video) do
    build_entry_for(video, :video_object)
  end

  defp build_entry_for(record, type) do
    progress_records = EntityShape.extract_progress(record, type)
    normalized = EntityShape.to_entity_view(record, type)
    build_entry_from_normalized(normalized, progress_records)
  end

  defp build_entry_from_normalized(entity, progress_records) do
    entity = pre_sort_children(entity)

    summary = ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: summary, progress_records: progress_records}
  end

  # --- Private Helpers ---

  defp pre_sort_children(entity) do
    seasons =
      (entity.seasons || [])
      |> EpisodeList.sort_seasons()
      |> Enum.map(fn season ->
        %{season | episodes: EpisodeList.sort_episodes(season.episodes || [])}
      end)

    movies = MovieList.sort_movies(entity.movies || [])

    %{entity | seasons: seasons, movies: movies}
  end
end
