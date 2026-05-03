defmodule MediaCentarr.Library.Browser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries.
  """
  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library.{EntityShape, Movie, MovieSeries, PresentableQueries, TVSeries, VideoObject}
  alias MediaCentarr.Library.{EpisodeList, MovieList, ProgressSummary}
  alias MediaCentarr.Repo
  alias MediaCentarr.Watcher.KnownFile

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

  Returns `{updated_entries, gone_ids}` where `gone_ids` contains IDs
  that no longer exist or have all files absent.
  """
  def fetch_typed_entries_by_ids(ids) do
    id_list = if is_list(ids), do: ids, else: MapSet.to_list(ids)

    movies = fetch_standalone_movies_by_ids(id_list)
    hoisted = fetch_hoisted_movies_by_ids(id_list)
    tv = fetch_tv_series_by_ids(id_list)
    ms = fetch_movie_series_by_ids(id_list)
    vo = fetch_video_objects_by_ids(id_list)

    entries =
      Enum.map(movies ++ hoisted ++ tv ++ ms ++ vo, &build_typed_entry/1)

    present_ids = MapSet.new(entries, fn entry -> entry.entity.id end)
    requested = MapSet.new(id_list)
    gone_ids = MapSet.difference(requested, present_ids)

    {entries, gone_ids}
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
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress])
  end

  defp fetch_hoisted_movies do
    PresentableQueries.singleton_collection_movies()
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress, :movie_series])
  end

  defp fetch_all_tv_series do
    from(t in TVSeries,
      as: :item,
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in KnownFile,
            on: kf.file_path == wf.file_path,
            where: wf.tv_series_id == parent_as(:item).id and kf.state == :present,
            select: 1
          )
        )
    )
    |> Repo.all()
    |> Repo.preload([
      :images,
      :external_ids,
      :watched_files,
      seasons: [episodes: [:images, :watch_progress]]
    ])
  end

  defp fetch_all_movie_series do
    PresentableQueries.multi_child_movie_series()
    |> Repo.all()
    |> Repo.preload([
      :images,
      :external_ids,
      :watched_files,
      movies: [:images, :watch_progress]
    ])
  end

  defp fetch_all_video_objects do
    from(v in VideoObject,
      as: :item,
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in KnownFile,
            on: kf.file_path == wf.file_path,
            where: wf.video_object_id == parent_as(:item).id and kf.state == :present,
            select: 1
          )
        )
    )
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress])
  end

  # --- Type-Specific Fetchers (by IDs) ---

  defp present_file_subquery(fk_column) do
    from(wf in "library_watched_files",
      join: kf in KnownFile,
      on: kf.file_path == wf.file_path,
      where: field(wf, ^fk_column) == parent_as(:item).id and kf.state == :present,
      select: 1
    )
  end

  defp fetch_standalone_movies_by_ids(ids) do
    from([m] in PresentableQueries.standalone_movies(), where: m.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress])
  end

  defp fetch_hoisted_movies_by_ids(ids) do
    from([m] in PresentableQueries.singleton_collection_movies(), where: m.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress, :movie_series])
  end

  defp fetch_tv_series_by_ids(ids) do
    from(t in TVSeries,
      as: :item,
      where: t.id in ^ids,
      where: exists(present_file_subquery(:tv_series_id))
    )
    |> Repo.all()
    |> Repo.preload([
      :images,
      :external_ids,
      :watched_files,
      seasons: [episodes: [:images, :watch_progress]]
    ])
  end

  defp fetch_movie_series_by_ids(ids) do
    from([ms] in PresentableQueries.multi_child_movie_series(), where: ms.id in ^ids)
    |> Repo.all()
    |> Repo.preload([
      :images,
      :external_ids,
      :watched_files,
      movies: [:images, :watch_progress]
    ])
  end

  defp fetch_video_objects_by_ids(ids) do
    from(v in VideoObject,
      as: :item,
      where: v.id in ^ids,
      where: exists(present_file_subquery(:video_object_id))
    )
    |> Repo.all()
    |> Repo.preload([:images, :external_ids, :watched_files, :watch_progress])
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
    normalized = EntityShape.normalize(record, type)
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
