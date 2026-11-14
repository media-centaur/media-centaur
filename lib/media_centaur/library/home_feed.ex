defmodule MediaCentaur.Library.HomeFeed do
  @moduledoc """
  Query + display-shaping for the home page's three feed rows: Continue
  Watching (`list_in_progress/2`, one profile's), Recently Added (`list_recently_added/1`),
  and the Hero banner (`list_hero_candidates/1`).

  Split out of the `Library` context (which keeps thin delegators) so the
  context isn't also a home-page view-shaping module. Returns plain display
  maps; the `Library.Views.*` ETS projections cache them and the LiveView
  renders them. Presence/hoist rules come from `PresentableQueries`.
  """

  import Ecto.Query

  alias MediaCentaur.ImageFiles

  alias MediaCentaur.Library.{
    Episode,
    Image,
    Movie,
    MovieSeries,
    PlayableItem,
    PresentableQueries,
    ProgressRecords,
    Season,
    SeriesWatchPosition,
    TitleProgress,
    TVSeries,
    VideoObject,
    WatchProgress
  }

  alias MediaCentaur.Repo

  @epoch_datetime ~U[1970-01-01 00:00:00Z]

  @doc """
  List `profile_id`'s in-progress titles, most recently watched first.
  Used by HomeLive's Continue Watching row.

  A title is in progress when its title progress
  (`MediaCentaur.Library.TitleProgress`) says so:

    * a TV series, from the first episode playback finished (or the first
      watched mark, or a viewing that counts) until its series watch
      position reaches the final episode — a rewatch included, whatever
      the watched marks say;
    * a movie or video, while its row has a viewing that counts
      (`ProgressRecords.viewing?/1`), a watched one being replayed
      included.

  A collection is never an entry; its member movies are (UIDR-025).

  Returns a list of plain maps in the shape:
    `%{entity_id, entity_name, progress_pct, backdrop_url, logo_url, last_watched_at}`

  `progress_pct` is `TitleProgress.percent/1`, 0..100, read at the live
  offset of a session in flight. `last_watched_at` is the title
  progress's, nil for a series only marked by hand, which sorts last.

  Includes entities whose underlying file is not currently present in any
  media_dir — Continue Watching is the user's mental list of "things I'm
  watching", and an absent file does not erase that. Playback handles the
  missing-file case at the action layer.

  A fixed number of queries whatever the size of the library, unless more
  finished series than one window holds were watched more recently than
  the unfinished ones (`in_progress_tv_series/2`).
  """
  @spec list_in_progress(Ecto.UUID.t(), keyword()) :: [map()]
  def list_in_progress(profile_id, opts \\ []) when is_binary(profile_id) do
    limit = Keyword.get(opts, :limit, 12)
    movies = in_progress_movie_candidates(profile_id, limit)
    video_objects = in_progress_video_object_candidates(profile_id, limit)

    progresses =
      ProgressRecords.title_progresses_by_kind(profile_id, %{
        movie: Enum.map(movies, & &1.id),
        video_object: Enum.map(video_objects, & &1.id)
      })

    (in_progress_entries(movies ++ video_objects, progresses) ++
       in_progress_tv_series(profile_id, limit))
    |> Enum.sort_by(&(&1.progress.last_watched_at || @epoch_datetime), {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&shape_in_progress_row/1)
  end

  # `%{entity, progress}` for each candidate whose title progress is in
  # progress, in candidate order. The candidate queries read persisted
  # rows; the title progress is read at the live offset, and is the
  # authority.
  defp in_progress_entries(entities, progresses) do
    for entity <- entities,
        %TitleProgress{state: :in_progress} = progress <- [progresses[entity.id]],
        do: %{entity: entity, progress: progress}
  end

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

  # When the profile last played each container whose playable items
  # point straight at it (movies, video objects) — the newest time among
  # its rows: the sort key of their candidate queries, as
  # `%{container_id, last_played_at}`.
  defp last_played_by_container(profile_id, container_type) do
    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id,
      where: wp.profile_id == ^profile_id and pi.container_type == ^container_type,
      group_by: pi.container_id,
      select: %{container_id: pi.container_id, last_played_at: max(wp.last_watched_at)}
    )
  end

  # Whether the movie or video object the parent query names (`:item`)
  # has a row of the profile's holding a viewing that counts — the SQL
  # twin of `ProgressRecords.viewing?/1`, applied before `limit`.
  defp counting_viewing_subquery(profile_id, container_type) do
    minimum = ProgressRecords.viewing_minimum_seconds()

    from(wp in WatchProgress,
      join: pi in PlayableItem,
      on: pi.id == wp.playable_item_id,
      where:
        wp.profile_id == ^profile_id and pi.container_type == ^container_type and
          pi.container_id == parent_as(:item).id and wp.position_seconds >= ^minimum,
      select: 1
    )
  end

  # Every movie with a viewing that counts, newest-watched first —
  # standalone or collection member alike. Per UIDR-025 the collection is
  # filing, not content: the unit of "continuing" is the member movie, so
  # there is no movie-vs-collection categorization on this surface at all.
  # Presence-agnostic (a transiently absent file doesn't erase the user's
  # intent to keep watching). The parent collection's images ride along
  # for the UIDR-021 art fallback.
  defp in_progress_movie_candidates(profile_id, limit) do
    from(m in Movie,
      as: :item,
      where: exists(counting_viewing_subquery(profile_id, :movie)),
      join: last_played in subquery(last_played_by_container(profile_id, :movie)),
      on: last_played.container_id == m.id,
      order_by: [desc: last_played.last_played_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload([:images, movie_series: :images])
    |> Enum.map(fn movie ->
      # Movie art first, collection art after — `image_url/2` takes the
      # first match per role, so a member missing its own backdrop or
      # logo inherits the collection's (UIDR-021 ladder).
      %{id: movie.id, name: movie.name, images: (movie.images || []) ++ collection_images(movie)}
    end)
  end

  defp collection_images(%Movie{movie_series: %MovieSeries{images: images}}), do: images || []
  defp collection_images(_movie), do: []

  # Every video object with a viewing of the profile's that counts.
  defp in_progress_video_object_candidates(profile_id, limit) do
    from(v in VideoObject,
      as: :item,
      where: exists(counting_viewing_subquery(profile_id, :video_object)),
      join: last_played in subquery(last_played_by_container(profile_id, :video_object)),
      on: last_played.container_id == v.id,
      order_by: [desc: last_played.last_played_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload([:images])
    |> Enum.map(&%{id: &1.id, name: &1.name, images: &1.images || []})
  end

  # How many candidate series one window holds, as a multiple of the
  # shelf's limit.
  @tv_series_window_factor 3

  # The TV series whose title progress is in progress, most recently
  # watched first, up to `limit`.
  #
  # Whether a series is in progress is the title-progress rule's answer
  # (its series watch position against its ordered set), which SQL cannot
  # give. So the candidates — every series the profile has touched — are
  # read most recently watched first, a window at a time, and each
  # window's title progress computed in bulk, until the limit is filled or
  # the candidates run out. A window is three times the limit: finished
  # series stay candidates for ever, and one window covers a profile whose
  # last two dozen series are finished. Each further window costs the same
  # few queries; the shelf is cached and rebuilt on progress events
  # (`Library.Views.ContinueWatching`).
  defp in_progress_tv_series(profile_id, limit) do
    found = collect_in_progress_tv_series(profile_id, limit, limit * @tv_series_window_factor, 0, [])
    series_list = found |> Enum.map(fn {series, _progress} -> series end) |> Repo.preload([:images])

    Enum.zip_with(series_list, found, fn series, {_series, progress} ->
      %{entity: %{id: series.id, name: series.name, images: series.images || []}, progress: progress}
    end)
  end

  # `[{series, progress}]`, newest first.
  defp collect_in_progress_tv_series(profile_id, limit, window, offset, found) do
    candidates = tv_series_candidates(profile_id, window, offset)

    progresses =
      ProgressRecords.title_progresses_by_kind(profile_id, %{tv_series: Enum.map(candidates, & &1.id)})

    found =
      found ++
        for series <- candidates,
            %TitleProgress{state: :in_progress} = progress <- [progresses[series.id]],
            do: {series, progress}

    if length(found) >= limit or length(candidates) < window do
      Enum.take(found, limit)
    else
      collect_in_progress_tv_series(profile_id, limit, window, offset + window, found)
    end
  end

  # One window of the series the profile has touched — any progress row
  # beneath it, or a series watch position — most recently watched first.
  # A series whose activity carries no time (hand marks only) sorts last.
  defp tv_series_candidates(profile_id, window, offset) do
    Repo.all(
      from(series in TVSeries,
        join: activity in subquery(tv_series_activity(profile_id)),
        on: activity.series_id == series.id,
        order_by: [desc: activity.activity_at, asc: series.id],
        limit: ^window,
        offset: ^offset
      )
    )
  end

  # `%{series_id, activity_at}` for every series the profile has touched:
  # the newest of its rows' times and its position's — the order the
  # candidates are read in, not the title progress's `last_watched_at`. A
  # series is watched through its episodes, so the rows roll up two
  # levels: episode -> season -> series.
  defp tv_series_activity(profile_id) do
    positions =
      from(position in SeriesWatchPosition,
        where: position.profile_id == ^profile_id and position.series_type == :tv_series,
        select: %{series_id: position.series_id, touched_at: position.finished_at}
      )

    rows =
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id,
        join: episode in Episode,
        on: episode.id == pi.container_id,
        join: season in Season,
        on: season.id == episode.season_id,
        where: wp.profile_id == ^profile_id and pi.container_type == ^:episode,
        select: %{series_id: season.tv_series_id, touched_at: wp.last_watched_at},
        union_all: ^positions
      )

    from(activity in subquery(rows),
      group_by: activity.series_id,
      select: %{series_id: activity.series_id, activity_at: max(activity.touched_at)}
    )
  end

  defp shape_in_progress_row(%{entity: entity, progress: progress}) do
    %{
      entity_id: entity.id,
      entity_name: entity.name,
      progress_pct: TitleProgress.percent(progress),
      backdrop_url: image_url(entity.images, "backdrop"),
      logo_url: image_url(entity.images, "logo"),
      last_watched_at: progress.last_watched_at
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
