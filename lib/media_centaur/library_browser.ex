defmodule MediaCentaur.LibraryBrowser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries and playback actions.
  """
  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library.{Entity, Movie, MovieSeries, TVSeries, VideoObject, WatchProgress}
  alias MediaCentaur.Playback.{EpisodeList, MovieList, ProgressSummary, Resolver, Sessions}
  alias MediaCentaur.Repo
  alias MediaCentaur.Watcher.KnownFile

  @full_preloads [
    :images,
    :identifiers,
    :watch_progress,
    :extras,
    :extra_progress,
    seasons: [:extras, episodes: :images],
    movies: :images
  ]

  @doc """
  Loads all entities with associations, computes progress summaries.

  Returns a list of `%{entity: entity, progress: summary, progress_records: records}`.
  """
  def fetch_entities do
    entities =
      Entity
      |> with_present_files()
      |> order_by(asc: :name)
      |> Repo.all()
      |> Repo.preload(@full_preloads)

    Log.info(:library, "loaded #{length(entities)} entities for browser")

    Enum.map(entities, &build_entry/1)
  end

  @doc """
  Loads specific entities by ID with full associations and progress.

  Returns `{updated_entries, gone_ids}` where `gone_ids` contains entity IDs
  that no longer exist or have all files absent.
  """
  def fetch_entries_by_ids(entity_ids) do
    entities =
      from(e in Entity, where: e.id in ^entity_ids)
      |> with_present_files()
      |> Repo.all()
      |> Repo.preload(@full_preloads)

    present_ids = MapSet.new(entities, & &1.id)
    requested = MapSet.new(entity_ids)
    gone_ids = MapSet.difference(requested, present_ids)

    entries = Enum.map(entities, &build_entry/1)

    {entries, gone_ids}
  end

  @doc """
  Smart play for any UUID — resolves the target and starts playback.
  """
  def play(uuid) do
    Log.info(:library, "play requested — #{Format.short_id(uuid)}")

    case Resolver.resolve(uuid) do
      {:ok, play_params} ->
        Sessions.play(play_params)

      {:error, reason} ->
        Log.info(:playback, "play failed — #{Format.short_id(uuid)}, #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Alternative query path that fetches from the type-specific tables
  (Movie, TVSeries, MovieSeries, VideoObject) instead of the Entity table.

  Returns the same entry format as `fetch_entities/0` so it can serve as
  a drop-in replacement once the transition is complete.

  Not yet wired into the LiveView — call manually for verification.
  """
  def fetch_all_typed_entries do
    standalone_movies = fetch_standalone_movies()
    tv_series = fetch_all_tv_series()
    movie_series = fetch_all_movie_series()
    video_objects = fetch_all_video_objects()

    entries =
      standalone_movies ++ tv_series ++ movie_series ++ video_objects

    Log.info(
      :library,
      "loaded #{length(entries)} typed entries for browser " <>
        "(#{length(standalone_movies)} movies, #{length(tv_series)} tv, " <>
        "#{length(movie_series)} movie series, #{length(video_objects)} video objects)"
    )

    entries
    |> Enum.map(&build_typed_entry/1)
    |> Enum.sort_by(fn entry -> (entry.entity.name || "") |> String.downcase() end)
  end

  # --- Type-Specific Fetchers ---

  defp fetch_standalone_movies do
    from(m in Movie,
      as: :item,
      where: is_nil(m.movie_series_id),
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in KnownFile,
            on: kf.file_path == wf.file_path,
            where: wf.movie_id == parent_as(:item).id and kf.state == :present,
            select: 1
          )
        )
    )
    |> Repo.all()
    |> Repo.preload([:images, :identifiers, :extras, :watched_files, :watch_progress])
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
      :identifiers,
      :extras,
      :watched_files,
      seasons: [:extras, episodes: :images]
    ])
  end

  defp fetch_all_movie_series do
    from(ms in MovieSeries,
      as: :item,
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in KnownFile,
            on: kf.file_path == wf.file_path,
            where: wf.movie_series_id == parent_as(:item).id and kf.state == :present,
            select: 1
          )
        )
    )
    |> Repo.all()
    |> Repo.preload([:images, :identifiers, :extras, :watched_files, movies: :images])
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
    |> Repo.preload([:images, :identifiers, :watched_files, :watch_progress])
  end

  # --- Typed Entry Builder ---
  #
  # Converts a type-specific struct into the same `%{entity: ..., progress: ..., progress_records: ...}`
  # format that `build_entry/1` produces from Entity records. This requires:
  #
  # 1. Fetching watch_progress through entity_id (since type table IDs == entity IDs)
  # 2. Normalizing the struct to a map with :type, :seasons, :movies, :extras, :extra_progress
  #    fields so ProgressSummary.compute and pre_sort_children work correctly.

  defp build_typed_entry(%Movie{} = movie) do
    progress_records = fetch_progress_for_id(movie.id)
    normalized = normalize_to_entity_shape(movie, :movie)
    build_entry_from_normalized(normalized, progress_records)
  end

  defp build_typed_entry(%TVSeries{} = series) do
    progress_records = fetch_progress_for_id(series.id)
    normalized = normalize_to_entity_shape(series, :tv_series)
    build_entry_from_normalized(normalized, progress_records)
  end

  defp build_typed_entry(%MovieSeries{} = series) do
    progress_records = fetch_progress_for_id(series.id)
    normalized = normalize_to_entity_shape(series, :movie_series)
    build_entry_from_normalized(normalized, progress_records)
  end

  defp build_typed_entry(%VideoObject{} = video) do
    progress_records = fetch_progress_for_id(video.id)
    normalized = normalize_to_entity_shape(video, :video_object)
    build_entry_from_normalized(normalized, progress_records)
  end

  defp fetch_progress_for_id(id) do
    from(wp in WatchProgress,
      where: wp.entity_id == ^id,
      order_by: [asc: :season_number, asc: :episode_number]
    )
    |> Repo.all()
  end

  defp normalize_to_entity_shape(record, type) do
    # Build a map with the fields that build_entry/pre_sort_children/ProgressSummary expect.
    # Missing associations default to empty lists to avoid nil access errors.
    %{
      __struct__: Entity,
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
      identifiers: Map.get(record, :identifiers, []),
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

  defp build_entry_from_normalized(entity, progress_records) do
    entity = entity |> pre_sort_children() |> maybe_unwrap_single_movie()

    summary = ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: summary, progress_records: progress_records}
  end

  # --- Private Helpers ---

  defp with_present_files(query) do
    from(e in query,
      where:
        fragment(
          """
          NOT EXISTS(SELECT 1 FROM library_watched_files WHERE entity_id = ?)
          OR EXISTS(
            SELECT 1 FROM library_watched_files lw
            WHERE lw.entity_id = ?
            AND NOT EXISTS(
              SELECT 1 FROM watcher_files wf
              WHERE wf.file_path = lw.file_path AND wf.state = 'absent'
            )
          )
          """,
          e.id,
          e.id
        )
    )
  end

  defp build_entry(entity) do
    entity = entity |> pre_sort_children() |> maybe_unwrap_single_movie()

    progress_records =
      Enum.sort_by(entity.watch_progress, &{&1.season_number, &1.episode_number})

    summary = ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: summary, progress_records: progress_records}
  end

  defp maybe_unwrap_single_movie(%{type: :movie_series, movies: [movie]} = entity) do
    %{
      entity
      | type: :movie,
        name: movie.name || entity.name,
        date_published: movie.date_published || entity.date_published,
        content_url: movie.content_url,
        movies: []
    }
  end

  defp maybe_unwrap_single_movie(entity), do: entity

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
