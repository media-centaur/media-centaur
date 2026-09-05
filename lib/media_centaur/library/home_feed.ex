defmodule MediaCentaur.Library.HomeFeed do
  @moduledoc """
  Query + display-shaping for the home page's three feed rows: Continue
  Watching (`list_in_progress/1`), Recently Added (`list_recently_added/1`),
  and the Hero banner (`list_hero_candidates/1`).

  Split out of the `Library` context (which keeps thin delegators) so the
  context isn't also a home-page view-shaping module. Returns plain display
  maps; the `Library.Views.*` ETS projections cache them and the LiveView
  renders them. Presence/hoist rules come from `PresentableQueries`.
  """

  import Ecto.Query

  alias MediaCentaur.ImageFiles

  alias MediaCentaur.Library.{
    ContinueWatchingProgress,
    Episode,
    Episodes,
    Image,
    Movie,
    MovieSeries,
    PlayableItem,
    PresentableQueries,
    Season,
    TVSeries,
    VideoObject,
    WatchProgress
  }

  alias MediaCentaur.Repo

  @epoch_datetime ~U[1970-01-01 00:00:00Z]

  @doc """
  List in-progress titles (those with watch progress that is not yet completed),
  most recently watched first. Used by HomeLive's Continue Watching row.

  Returns a list of plain maps in the shape:
    `%{entity_id, entity_name, progress_pct, backdrop_url}`

  `progress_pct` is 0..100 (integer).

  Includes entities whose underlying file is not currently present in any
  media_dir — Continue Watching is the user's mental list of "things I'm
  watching", and an absent file does not erase that. Playback handles the
  missing-file case at the action layer.

  Issues at most ~15 targeted queries regardless of library size, compared to
  the ~87 queries of the previous `fetch_all_typed_entries` approach.
  """
  @spec list_in_progress(keyword()) :: [map()]
  def list_in_progress(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    movie_entries = fetch_in_progress_movies(limit)
    tv_series_entries = fetch_in_progress_tv_series(limit)
    video_object_entries = fetch_in_progress_video_objects(limit)

    (movie_entries ++ tv_series_entries ++ video_object_entries)
    |> Enum.map(&overlay_in_memory_progress/1)
    |> Enum.sort_by(
      fn entry -> entry_last_watched_at(entry) || @epoch_datetime end,
      {:desc, DateTime}
    )
    |> Enum.take(limit)
    |> Enum.map(&shape_in_progress_row/1)
  end

  # Overlays the hot-path in-memory `WatchProgress` state on top of the
  # DB-preloaded progress records so Continue Watching reflects the live
  # position during active playback. Without this, the persisted row is
  # ~5s stale (the `MediaCentaur.Library.Progress` debounced-flush
  # interval), so the bar visibly lags playback. Closes the same
  # stale-read window the `Playback.ProgressBroadcaster` overlay
  # closes for the modal — Library Schema v2 Phase 3 Task E I-2.
  #
  # Re-runs the per-record overlay AND patches the `progress`
  # summary's `episode_position_seconds` / `episode_duration_seconds`
  # so `ContinueWatchingProgress.compute_pct/1` (which reads from the
  # summary, not the records) sees the fresh numbers. `completed` stays
  # DB-authoritative — see `MediaCentaur.Library.Progress.overlay_in_memory/1`.
  defp overlay_in_memory_progress(%{progress_records: records, progress: summary} = entry) do
    fresh = Enum.map(records, &MediaCentaur.Library.Progress.overlay_in_memory/1)

    refreshed_summary =
      Map.merge(summary, ContinueWatchingProgress.current_position_summary(fresh))

    %{entry | progress_records: fresh, progress: refreshed_summary}
  end

  defp overlay_in_memory_progress(entry), do: entry

  @doc """
  List recently-added entities (newest `inserted_at` first), regardless of
  entity type. Returns plain maps in the shape:
    `%{id, name, year, poster_url}`

  Issues at most 8 queries: one per entity type + one image preload per type,
  compared to ~87 queries for the previous `fetch_all_typed_entries` approach.
  """
  @spec list_recently_added(keyword()) :: [map()]
  def list_recently_added(opts \\ []) do
    limit = Keyword.get(opts, :limit, 16)

    # One base query per content type; each carries its own presence
    # filter, and `fetch_recently_added/2` applies the uniform newest-first /
    # limit / image-preload / row-shape tail. Concatenation order is the
    # stable tie-break for equal `inserted_at`. Movies are one query with
    # no collection categorization — the new thing is the movie, never its
    # collection container (UIDR-025).
    [
      PresentableQueries.present_movies(),
      from(t in TVSeries,
        as: :item,
        where: exists(PresentableQueries.tv_series_present_file_subquery())
      ),
      from(v in VideoObject,
        as: :item,
        where: exists(PresentableQueries.video_object_present_file_subquery())
      )
    ]
    |> Enum.flat_map(&fetch_recently_added(&1, limit))
    |> Enum.sort_by(& &1.__inserted_at__, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :__inserted_at__))
  end

  defp fetch_recently_added(base_query, limit) do
    base_query
    |> order_by([x], desc: x.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  @doc """
  List entities suitable as Home page hero (those with both a backdrop
  image and a description). Returns plain maps in the shape:
    `%{id, name, year, runtime_minutes, genres, overview, backdrop_url}`

  The eligibility filter (backdrop + description) is the real curation —
  the library is already a user-curated set — so the result is unbounded
  by default. Pass `:limit` to cap it (callers/benchmarks/tests).

  Issues at most 8 queries: one per entity type + one image preload per type,
  compared to ~87 queries for the previous `fetch_all_typed_entries` approach.
  """
  @spec list_hero_candidates(keyword()) :: [map()]
  def list_hero_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit)

    # One base query per content type, paired with the owner_type its
    # backdrop image is keyed by. Each base query carries its own presence
    # filter; `fetch_hero_candidates/3` adds the uniform eligibility
    # (non-blank description + a backdrop image), newest-first ordering, and
    # row shaping. Results stay type-grouped (movies, tv, …) then capped —
    # no global re-sort. Collection members are candidates on their own
    # art and synopsis; the collection entity never is (UIDR-025).
    [
      {PresentableQueries.present_movies(), :movie},
      {from(t in TVSeries,
         as: :item,
         where: exists(PresentableQueries.tv_series_present_file_subquery())
       ), :tv_series},
      {from(v in VideoObject,
         as: :item,
         where: exists(PresentableQueries.video_object_present_file_subquery())
       ), :video_object}
    ]
    |> Enum.flat_map(fn {query, owner_type} -> fetch_hero_candidates(query, owner_type, limit) end)
    |> maybe_take(limit)
  end

  # --- Private fetchers for list_hero_candidates ---

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, limit), do: Enum.take(list, limit)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: from(q in query, limit: ^limit)

  # Adds the uniform hero eligibility to a per-type base query (aliased
  # `:item`): a non-blank description and a backdrop image of the matching
  # `owner_type`, newest first, then shapes each row. The base query owns
  # the per-type presence filter.
  defp fetch_hero_candidates(base_query, owner_type, limit) do
    base_query
    |> where([item], not is_nil(item.description) and fragment("TRIM(?)", item.description) != "")
    |> where([item], exists(hero_backdrop_subquery(owner_type)))
    |> order_by([item], desc: item.inserted_at)
    |> maybe_limit(limit)
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_hero_record/1)
  end

  defp hero_backdrop_subquery(owner_type) do
    from(img in Image,
      where:
        img.owner_id == parent_as(:item).id and img.owner_type == ^owner_type and
          img.role == "backdrop" and not is_nil(img.content_url),
      select: 1
    )
  end

  # "When did the user last watch anything inside this title?" — the sort key
  # every Continue Watching fetcher orders by. It is a question about the
  # title's playable items, not the title itself, so each variant below
  # answers it for one container shape and returns the one shape the callers
  # join against: `%{container_id, last_watched_at}`.
  #
  # These were four hand-written SQL fragments naming five tables as string
  # literals, which a schema rename would have broken silently — the query
  # would still run and simply stop sorting. Expressed in Ecto, the same
  # rename is a compile error.
  #
  # Callers inner-join these: every fetcher already requires an existing
  # progress record via its first `exists`, so there is no row to preserve
  # with a left join. `max/1` also replaces two `LIMIT 1`s that took an
  # arbitrary progress row for titles with more than one playable item.

  # Every WatchProgress row beneath a set of series, grouped by series, in
  # one query. Replaces a per-episode lookup that first needed every episode
  # id in memory to ask the question.
  defp progress_records_by_tv_series([]), do: %{}

  defp progress_records_by_tv_series(series_ids) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id,
      join: episode in Episode,
      on: episode.id == pi.container_id,
      join: season in Season,
      on: season.id == episode.season_id,
      where: pi.container_type == ^:episode and season.tv_series_id in ^series_ids,
      select: {season.tv_series_id, wp}
    )
    |> Repo.all()
    |> Enum.group_by(fn {series_id, _progress} -> series_id end, fn {_id, progress} -> progress end)
  end

  # Containers whose playable items point straight at them (movies, video
  # objects).
  defp last_watched_by_container(container_type) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id,
      where: pi.container_type == ^container_type,
      group_by: pi.container_id,
      select: %{container_id: pi.container_id, last_watched_at: max(wp.last_watched_at)}
    )
  end

  # A series is watched through its episodes, so the progress rolls up two
  # levels: episode -> season -> series.
  defp last_watched_by_tv_series do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id,
      join: episode in Episode,
      on: episode.id == pi.container_id,
      join: season in Season,
      on: season.id == episode.season_id,
      where: pi.container_type == ^:episode,
      group_by: season.tv_series_id,
      select: %{container_id: season.tv_series_id, last_watched_at: max(wp.last_watched_at)}
    )
  end

  # Every movie with an incomplete WatchProgress, newest-watched first —
  # standalone or collection member alike. Per UIDR-025 the collection is
  # filing, not content: the unit of "continuing" is the member movie, so
  # there is no movie-vs-collection categorization on this surface at all.
  # Presence-agnostic (a transiently absent file doesn't erase the user's
  # intent to keep watching). The parent collection's images ride along
  # for the UIDR-021 art fallback.
  defp fetch_in_progress_movies(limit) do
    from(m in Movie,
      as: :item,
      where:
        exists(
          from(wp in WatchProgress,
            join: pi in PlayableItem,
            on: pi.id == wp.playable_item_id,
            where:
              pi.container_type == ^:movie and pi.container_id == parent_as(:item).id and
                wp.completed == false,
            select: 1
          )
        ),
      join: last_watched in subquery(last_watched_by_container(:movie)),
      on: last_watched.container_id == m.id,
      order_by: [desc: last_watched.last_watched_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload([:images, :watch_progress, movie_series: :images])
    |> Enum.map(&build_in_progress_movie_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp build_in_progress_movie_entry(movie) do
    single_leaf_entry(
      %{
        id: movie.id,
        type: :movie,
        name: movie.name,
        description: movie.description,
        # Movie art first, collection art after — `image_url/2` takes the
        # first match per role, so a member missing its own backdrop or
        # logo inherits the collection's (UIDR-021 ladder).
        images: (movie.images || []) ++ collection_images(movie),
        genres: movie.genres,
        duration_seconds: movie.duration_seconds
      },
      movie.watch_progress
    )
  end

  # `%{entity, progress, progress_records}` for a container with exactly one
  # playable leaf (movie, video object), or nil unless its one progress
  # record is unfinished. One unfinished record means nothing is completed.
  defp single_leaf_entry(_entity, nil), do: nil
  defp single_leaf_entry(_entity, %{completed: true}), do: nil

  defp single_leaf_entry(entity, progress_record) do
    progress_records = [progress_record]

    progress =
      Map.merge(
        %{episodes_completed: 0, episodes_total: 1},
        ContinueWatchingProgress.current_position_summary(progress_records)
      )

    %{entity: entity, progress: progress, progress_records: progress_records}
  end

  defp collection_images(%Movie{movie_series: %MovieSeries{images: images}}), do: images || []
  defp collection_images(_movie), do: []

  # Fetches TV series the user has started but not finished.
  #
  # Both halves of "in progress" are tested in SQL, before `limit`. The
  # unfinished test used to run in Elixir after the fetch, so a window full
  # of finished series was fetched, rejected, and left the row short.
  defp fetch_in_progress_tv_series(limit) do
    series_list =
      from(t in TVSeries,
        as: :series,
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              join: ep in Episode,
              on: ep.id == pi.container_id and pi.container_type == ^:episode,
              join: s in Season,
              on: s.id == ep.season_id,
              where: s.tv_series_id == parent_as(:series).id,
              select: 1
            )
          ),
        where:
          exists(
            from(ep in Episode,
              as: :episode,
              join: s in Season,
              on: s.id == ep.season_id,
              where: s.tv_series_id == parent_as(:series).id,
              where:
                not exists(
                  from(wp in WatchProgress,
                    join: pi in PlayableItem,
                    on: pi.id == wp.playable_item_id,
                    where:
                      pi.container_type == ^:episode and
                        pi.container_id == parent_as(:episode).id and
                        wp.completed == true,
                    select: 1
                  )
                ),
              select: 1
            )
          ),
        join: last_watched in subquery(last_watched_by_tv_series()),
        on: last_watched.container_id == t.id,
        order_by: [desc: last_watched.last_watched_at],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images])

    # The two numbers this row needs from the episode list — how many
    # present episodes there are, and which of them have progress — are
    # both aggregates, so they are asked for as aggregates. Preloading
    # `seasons: [:episodes]` to compute them loaded every episode of every
    # returned series into memory to produce two integers apiece.
    series_ids = Enum.map(series_list, & &1.id)
    progress_by_series = progress_records_by_tv_series(series_ids)
    episode_counts = Episodes.count_available_by_tv_series(series_ids)

    Enum.reject(
      Enum.map(series_list, fn series ->
        progress_records = Map.get(progress_by_series, series.id, [])
        episodes_total = Map.get(episode_counts, series.id, 0)
        episodes_completed = Enum.count(progress_records, & &1.completed)

        # Include series when the user has touched it (any progress) AND
        # hasn't finished all episodes.
        if progress_records != [] and episodes_completed < episodes_total do
          entity = %{
            id: series.id,
            type: :tv_series,
            name: series.name,
            description: series.description,
            images: series.images || [],
            genres: series.genres,
            duration_seconds: nil
          }

          progress =
            Map.merge(
              %{episodes_completed: episodes_completed, episodes_total: episodes_total},
              ContinueWatchingProgress.current_position_summary(progress_records)
            )

          %{entity: entity, progress: progress, progress_records: progress_records}
        end
      end),
      &is_nil/1
    )
  end

  # Fetches video objects with at least one incomplete WatchProgress record.
  defp fetch_in_progress_video_objects(limit) do
    video_objects =
      from(v in VideoObject,
        as: :video_object,
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              where:
                pi.container_type == ^:video_object and
                  pi.container_id == parent_as(:video_object).id and
                  wp.completed == false,
              select: 1
            )
          ),
        join: last_watched in subquery(last_watched_by_container(:video_object)),
        on: last_watched.container_id == v.id,
        order_by: [desc: last_watched.last_watched_at],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, :watch_progress])

    Enum.reject(
      Enum.map(video_objects, fn video_object ->
        single_leaf_entry(
          %{
            id: video_object.id,
            type: :video_object,
            name: video_object.name,
            description: video_object.description,
            images: video_object.images || [],
            genres: nil,
            duration_seconds: nil
          },
          video_object.watch_progress
        )
      end),
      &is_nil/1
    )
  end

  defp entry_last_watched_at(%{progress_records: records}) do
    records
    |> Enum.map(& &1.last_watched_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp shape_in_progress_row(%{entity: entity, progress: summary, progress_records: records}) do
    backdrop_url = image_url(entity.images, "backdrop")
    logo_url = image_url(entity.images, "logo")

    progress_pct = ContinueWatchingProgress.compute_pct(summary)

    last_watched_at = entry_last_watched_at(%{progress_records: records})

    %{
      entity_id: entity.id,
      entity_name: entity.name,
      progress_pct: progress_pct,
      backdrop_url: backdrop_url,
      logo_url: logo_url,
      last_watched_at: last_watched_at
    }
  end

  # Shapes a record (Movie, TVSeries, MovieSeries, VideoObject struct) into
  # the recently-added plain map. Carries `__inserted_at__` for merge-sort,
  # dropped by the caller before returning to HomeLive.
  defp shape_recently_added_record(record) do
    poster_url =
      case Enum.find(record.images || [], &(&1.role == "poster")) do
        %{content_url: url} when is_binary(url) -> ImageFiles.web_path(url)
        _ -> nil
      end

    %{
      id: record.id,
      name: record.name,
      year: record_year(record),
      poster_url: poster_url,
      __inserted_at__: record.inserted_at
    }
  end

  # Shapes a record (Movie, TVSeries, MovieSeries, VideoObject struct with
  # images preloaded) into the hero candidate plain map.
  defp shape_hero_record(record) do
    backdrop_url = image_url(record.images, "backdrop")
    logo_url = image_url(record.images, "logo")

    runtime_minutes =
      case Map.get(record, :duration_seconds) do
        seconds when is_integer(seconds) and seconds > 0 -> div(seconds, 60)
        _ -> nil
      end

    %{
      id: record.id,
      name: record.name,
      year: record_year(record),
      runtime_minutes: runtime_minutes,
      genres: Map.get(record, :genres),
      overview: record.description,
      backdrop_url: backdrop_url,
      logo_url: logo_url
    }
  end

  # Extracts the year from a record's `date_published` field. Returns `nil`
  # when the record has no date or the field isn't a `%Date{}` (e.g. a plain
  # map shape from upstream callers).
  defp record_year(%{date_published: %Date{year: y}}), do: y
  defp record_year(_), do: nil

  defp image_url(images, role) do
    case Enum.find(images || [], &(&1.role == role)) do
      %{content_url: url} when is_binary(url) -> ImageFiles.web_path(url)
      _ -> nil
    end
  end
end
