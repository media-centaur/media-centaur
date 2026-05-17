defmodule MediaCentarr.Library.Browser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries.
  """
  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library.{
    EntityShape,
    Episode,
    Movie,
    MovieSeries,
    PlayableItem,
    PresentableQueries,
    Season,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  alias MediaCentarr.Library
  alias MediaCentarr.Library.{EpisodeList, MovieList, ProgressSummary}
  alias MediaCentarr.Repo

  # Leaf preload chain for materialising the virtual `Episode.content_url` /
  # `Movie.content_url` / `VideoObject.content_url` field (Library Schema
  # v2 Phase 2 Task I). `Library.populate_content_urls/1` walks
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
  """
  def fetch_all_typed_entries do
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
    |> Enum.sort_by(fn entry -> String.downcase(entry.entity.name || "") end)
  end

  @doc """
  Loads specific entries by ID from the type-specific tables.

  `type_hints` maps known IDs to their entity type
  (`:movie | :tv_series | :movie_series | :video_object`). When the LiveView
  has already loaded the entity once, the type is known and the lookup
  routes to a single type-specific table — skipping 4 of 5 fetcher queries.
  IDs absent from `type_hints` (newly inserted entities the LiveView hasn't
  seen yet) fall back to the full all-types fan-out.

  Returns `{updated_entries, gone_ids}` where `gone_ids` contains IDs
  that no longer exist or have all files absent.
  """
  def fetch_typed_entries_by_ids(ids, type_hints \\ %{}) do
    id_list = if is_list(ids), do: ids, else: MapSet.to_list(ids)
    {known_typed, unknown_typed} = partition_by_known_type(id_list, type_hints)

    typed_records =
      known_typed
      |> Enum.flat_map(fn {type, ids} -> fetch_records_for_type(type, ids) end)
      |> Kernel.++(fetch_all_types(unknown_typed))

    entries = Enum.map(typed_records, &build_typed_entry/1)

    present_ids = MapSet.new(entries, fn entry -> entry.entity.id end)
    requested = MapSet.new(id_list)
    gone_ids = MapSet.difference(requested, present_ids)

    {entries, gone_ids}
  end

  defp partition_by_known_type(ids, type_hints) do
    {known, unknown} = Enum.split_with(ids, &Map.has_key?(type_hints, &1))

    known_grouped =
      known
      |> Enum.group_by(&Map.fetch!(type_hints, &1))
      |> Map.to_list()

    {known_grouped, unknown}
  end

  # Standalone vs hoisted movies are both Movie records distinguished by the
  # PresentableQueries.singleton_collection_movies/0 predicate (parent
  # MovieSeries has exactly one child). Either fetcher may return a record
  # for a given movie id; both query the same library_movies table. Calling
  # both for the :movie hint preserves the standalone/hoisted split.
  defp fetch_records_for_type(:movie, []), do: []

  defp fetch_records_for_type(:movie, ids) do
    fetch_standalone_movies_by_ids(ids) ++ fetch_hoisted_movies_by_ids(ids)
  end

  defp fetch_records_for_type(:tv_series, []), do: []
  defp fetch_records_for_type(:tv_series, ids), do: fetch_tv_series_by_ids(ids)
  defp fetch_records_for_type(:movie_series, []), do: []
  defp fetch_records_for_type(:movie_series, ids), do: fetch_movie_series_by_ids(ids)
  defp fetch_records_for_type(:video_object, []), do: []
  defp fetch_records_for_type(:video_object, ids), do: fetch_video_objects_by_ids(ids)

  defp fetch_all_types([]), do: []

  defp fetch_all_types(ids) do
    fetch_standalone_movies_by_ids(ids) ++
      fetch_hoisted_movies_by_ids(ids) ++
      fetch_tv_series_by_ids(ids) ++
      fetch_movie_series_by_ids(ids) ++
      fetch_video_objects_by_ids(ids)
  end

  # --- Type-Specific Fetchers (all) ---
  #
  # All fetchers use `Repo.all |> Repo.preload(...)`, which issues one query
  # per (association, parent type) pair via an `IN` clause. The total cost is
  # a bounded constant (~29 queries) that does NOT scale with row count. This
  # is the standard Ecto preload pattern, not N+1, and is enforced as a
  # regression by `test/media_centarr/library_browser_test.exs` — see the
  # "query count (N+1 regression guard)" describe block.

  defp fetch_standalone_movies do
    PresentableQueries.standalone_movies()
    |> Repo.all()
    |> Repo.preload(@standalone_movie_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_hoisted_movies do
    PresentableQueries.singleton_collection_movies()
    |> Repo.all()
    |> Repo.preload(@hoisted_movie_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_all_tv_series do
    from(t in TVSeries,
      as: :item,
      where: exists(tv_series_present_file_subquery())
    )
    |> Repo.all()
    |> Repo.preload(@tv_series_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_all_movie_series do
    PresentableQueries.multi_child_movie_series()
    |> Repo.all()
    |> Repo.preload(@movie_series_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_all_video_objects do
    from(v in VideoObject,
      as: :item,
      where: exists(video_object_present_file_subquery())
    )
    |> Repo.all()
    |> Repo.preload(@video_object_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  # --- Type-Specific Fetchers (by IDs) ---

  # WatchedFile → PlayableItem(:episode) → Episode → Season → TVSeries
  # presence subquery, scoped to the outer `:item` (a TVSeries) binding.
  # Phase-3 cascade-delete from Library.FilePresence makes WatchedFile
  # existence equivalent to "current presence on disk."
  defp tv_series_present_file_subquery do
    from(wf in WatchedFile,
      join: pi in PlayableItem,
      on: pi.id == wf.playable_item_id and pi.container_type == :episode,
      join: e in Episode,
      on: e.id == pi.container_id,
      join: s in Season,
      on: s.id == e.season_id,
      where: s.tv_series_id == parent_as(:item).id,
      select: 1
    )
  end

  # WatchedFile → PlayableItem(:video_object) presence subquery scoped to
  # the outer `:item` (a VideoObject) binding.
  defp video_object_present_file_subquery do
    from(wf in WatchedFile,
      join: pi in PlayableItem,
      on: pi.id == wf.playable_item_id and pi.container_type == :video_object,
      where: pi.container_id == parent_as(:item).id,
      select: 1
    )
  end

  defp fetch_standalone_movies_by_ids(ids) do
    from([m] in PresentableQueries.standalone_movies(), where: m.id in ^ids)
    |> Repo.all()
    |> Repo.preload(@standalone_movie_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_hoisted_movies_by_ids(ids) do
    from([m] in PresentableQueries.singleton_collection_movies(), where: m.id in ^ids)
    |> Repo.all()
    |> Repo.preload(@hoisted_movie_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_tv_series_by_ids(ids) do
    from(t in TVSeries,
      as: :item,
      where: t.id in ^ids,
      where: exists(tv_series_present_file_subquery())
    )
    |> Repo.all()
    |> Repo.preload(@tv_series_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_movie_series_by_ids(ids) do
    from([ms] in PresentableQueries.multi_child_movie_series(), where: ms.id in ^ids)
    |> Repo.all()
    |> Repo.preload(@movie_series_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  defp fetch_video_objects_by_ids(ids) do
    from(v in VideoObject,
      as: :item,
      where: v.id in ^ids,
      where: exists(video_object_present_file_subquery())
    )
    |> Repo.all()
    |> Repo.preload(@video_object_preloads)
    |> Enum.map(&Library.populate_content_urls/1)
  end

  # --- Typed Entry Builder ---
  #
  # Converts a type-specific struct into the same `%{entity: ..., progress: ..., progress_records: ...}`
  # format used by the LiveView. Progress records are extracted from preloaded associations
  # (no separate query needed). The struct is normalized to a map with :type, :seasons, :movies,
  # :extras, :extra_progress fields so ProgressSummary.compute and pre_sort_children work correctly.

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
    normalized = EntityShape.to_view_model(record, type)
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
