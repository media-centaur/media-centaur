defmodule MediaCentarr.Showcase do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Populates a showcase profile database with curated, legally-safe media.

  The catalog is public-domain and CC-licensed titles — Blender open movies,
  early silent films, and classic public-domain horror/sci-fi — so seed data
  can ship in marketing screenshots without copyright concerns.

  Entry point: `MediaCentarr.Showcase.seed!/0`. The Mix task
  `mix seed.showcase` is a thin wrapper around it that additionally refuses
  to run against the default profile as a safety rail.

  ## Content policy: PD or CC only, every string

  **Every title string surfaced by the showcase must be public-domain or
  Creative Commons.** The policy applies to every reference, not just the
  library catalog:

    * `MediaCentarr.Showcase.Catalog` — movies, TV series, video objects.
    * Release-tracking items in `seed_release_tracking!` — even though
      tracked items render "metadata only" (title + poster + date), the
      title string itself ships in screenshots, so an IMDb-style fair-use
      bridge does **not** apply here. Use PD/CC titles only.
    * Acquisition grab titles in `seed_acquisition_activity!` — visible in
      the `/download` Activity tab; subject to the same rule.
    * Pending review fixtures in `pending_file_data` — visible in the
      Review queue screenshots.
    * Console log lines in `seed_console_entries!` — visible in the
      Console drawer screenshot.

  Note on borderline titles: *House on Haunted Hill (1959)* is **not**
  treated as public-domain by this project despite being widely listed as
  such — keep it out. The curated PD list is the canonical source: Blender
  open movies, pre-1928 silents, and renewal-failure films like Night of
  the Living Dead, Plan 9 from Outer Space, Carnival of Souls, The Last
  Man on Earth, plus CC titles like Sita Sings the Blues and Pioneer One.

  Parser regression tests under `test/media_centarr/parser_test.exs` are
  exempt: those filenames are real-world paths the parser has been
  observed to encounter, are append-only per ADR-027, and are never
  rendered to a screenshot or marketing surface.

  ## Data created

    * Library records (Movie, TVSeries, Season, Episode, MovieSeries, VideoObject)
      with real TMDB metadata and downloaded poster+backdrop images.
    * Watch progress rows (mix of partial and completed) on a subset of items.
    * Release-tracking items with synthetic future air dates so the Status page
      has upcoming + available releases to display.
    * Pending review files covering the full palette of review UI states.
    * Watch-history events so the /history page is populated.

  All TMDB lookups go through `MediaCentarr.TMDB.Client` which honours the
  persistent-term stub used by tests — so `mix test` never hits the real API.
  """

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Library
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.Repo
  alias MediaCentarr.Review
  alias MediaCentarr.Showcase.Catalog
  alias MediaCentarr.TMDB
  alias MediaCentarr.Watcher.FilePresence
  alias MediaCentarr.WatchHistory

  require MediaCentarr.Log, as: Log

  @type summary :: %{
          movies: non_neg_integer(),
          tv_series: non_neg_integer(),
          seasons: non_neg_integer(),
          episodes: non_neg_integer(),
          video_objects: non_neg_integer(),
          watch_progress: non_neg_integer(),
          tracked_items: non_neg_integer(),
          pending_files: non_neg_integer(),
          watch_events: non_neg_integer(),
          acquisitions: non_neg_integer()
        }

  @doc """
  Seeds the currently-connected database with the showcase catalog.

  Returns a summary map with per-entity counts. Raises if the configured
  `:database_path` doesn't look like a showcase DB — see
  `assert_showcase_db!/0`. The Mix task wrapper (`mix seed.showcase`)
  adds a second env-var check; this function itself covers the
  direct-IEx-invocation path.
  """
  @spec seed!() :: summary()
  def seed! do
    assert_showcase_db!()
    client = TMDB.Client.default_client()

    movies = Enum.map(Catalog.movies(), &seed_movie!(&1, client))
    tv_series = Enum.map(Catalog.tv_series(), &seed_tv_series!(&1, client))
    video_objects = Enum.map(Catalog.video_objects(), &seed_video_object!/1)

    counts = %{
      watch_progress: seed_watch_progress!(movies, tv_series),
      tracked_items: seed_release_tracking!(client),
      pending_files: seed_pending_files!(client),
      watch_events: seed_watch_history!(movies, tv_series),
      acquisitions: seed_acquisition_activity!()
    }

    seed_fake_capabilities!()
    seed_console_entries!()

    build_summary(movies, tv_series, video_objects, counts)
  end

  defp build_summary(movies, tv_series, video_objects, counts) do
    Map.merge(counts, %{
      movies: length(movies),
      tv_series: length(tv_series),
      seasons: count_seasons(tv_series),
      episodes: count_episodes(tv_series),
      video_objects: length(video_objects)
    })
  end

  defp count_seasons(tv_series), do: tv_series |> Enum.map(&length(&1.seasons)) |> Enum.sum()

  defp count_episodes(tv_series) do
    tv_series
    |> Enum.flat_map(& &1.seasons)
    |> Enum.map(&length(&1.episodes))
    |> Enum.sum()
  end

  # ---------------------------------------------------------------------------
  # Movies
  # ---------------------------------------------------------------------------

  defp seed_movie!(%{title: title, year: year} = entry, client) do
    with {:ok, tmdb_id} <- search_movie(title, year, client),
         {:ok, movie_data} <- TMDB.Client.get_movie(tmdb_id, client) do
      movie =
        Library.create_movie!(%{
          name: movie_data["title"] || title,
          description: movie_data["overview"],
          date_published: movie_data["release_date"],
          duration: minutes_to_iso(movie_data["runtime"]),
          genres: extract_genre_names(movie_data["genres"]),
          url: "https://www.themoviedb.org/movie/#{tmdb_id}",
          aggregate_rating_value: movie_data["vote_average"],
          tmdb_id: to_string(tmdb_id),
          content_url: Map.get(entry, :content_url),
          position: 0
        })

      download_images!(movie.id, movie_data, :movie_id)

      Library.find_or_create_external_id!(%{
        movie_id: movie.id,
        source: "tmdb",
        external_id: to_string(tmdb_id)
      })

      seed_presence!(movie.id, :movie_id, fake_movie_path(movie.name))

      movie
    else
      {:error, reason} ->
        raise """
        showcase seed failed for movie "#{title}" (#{year}): #{inspect(reason)}.

        TMDB lookups must succeed for the seed to produce usable data.
        Set TMDB_API_KEY to a valid key before running `mix seed.showcase`
        (scripts/start-showcase inherits it from the dev DB's stored key).
        """
    end
  end

  # ---------------------------------------------------------------------------
  # TV Series
  # ---------------------------------------------------------------------------

  defp seed_tv_series!(%{title: title, year: year, seasons: season_numbers} = _entry, client) do
    with {:ok, tmdb_id} <- search_tv(title, year, client),
         {:ok, tv_data} <- TMDB.Client.get_tv(tmdb_id, client) do
      series =
        Library.create_tv_series!(%{
          name: tv_data["name"] || title,
          description: tv_data["overview"],
          date_published: tv_data["first_air_date"],
          genres: extract_genre_names(tv_data["genres"]),
          url: "https://www.themoviedb.org/tv/#{tmdb_id}",
          aggregate_rating_value: tv_data["vote_average"],
          number_of_seasons: tv_data["number_of_seasons"]
        })

      download_images!(series.id, tv_data, :tv_series_id)

      Library.find_or_create_external_id!(%{
        tv_series_id: series.id,
        source: "tmdb",
        external_id: to_string(tmdb_id)
      })

      seasons =
        Enum.map(season_numbers, fn season_number ->
          seed_season!(series, tmdb_id, season_number, client)
        end)

      # One file-presence row per episode so the TV detail modal shows
      # each episode as "in library" (not a missing-file state).
      seasons
      |> Enum.flat_map(& &1.episodes)
      |> Enum.filter(& &1.id)
      |> Enum.each(fn episode ->
        seed_presence!(
          series.id,
          :tv_series_id,
          fake_episode_path(series.name, episode_season_number(episode, seasons), episode.episode_number)
        )
      end)

      Map.put(series, :seasons, seasons)
    else
      {:error, reason} ->
        raise """
        showcase seed failed for TV series "#{title}" (#{year}): #{inspect(reason)}.

        TMDB lookups must succeed for the seed to produce usable data.
        Set TMDB_API_KEY to a valid key before running `mix seed.showcase`
        (scripts/start-showcase inherits it from the dev DB's stored key).
        """
    end
  end

  defp seed_season!(series, tmdb_id, season_number, client) do
    case TMDB.Client.get_season(tmdb_id, season_number, client) do
      {:ok, season_data} ->
        season =
          Library.create_season!(%{
            tv_series_id: series.id,
            season_number: season_number,
            name: season_data["name"] || "Season #{season_number}",
            number_of_episodes: length(season_data["episodes"] || [])
          })

        episodes =
          Enum.map(season_data["episodes"] || [], fn ep_data ->
            seed_episode!(season, ep_data, series.name)
          end)

        Map.put(season, :episodes, episodes)

      {:error, reason} ->
        Log.warning(:library, "showcase: failed to seed season #{season_number}: #{inspect(reason)}")
        %{id: nil, episodes: []}
    end
  end

  defp seed_episode!(season, ep_data, series_name) do
    episode_number = ep_data["episode_number"]
    episode_name = ep_data["name"] || "Episode #{episode_number}"

    episode =
      Library.create_episode!(%{
        season_id: season.id,
        episode_number: episode_number,
        name: episode_name,
        description: ep_data["overview"],
        duration: minutes_to_iso(ep_data["runtime"]),
        content_url: fake_episode_path(series_name, season.season_number, episode_number)
      })

    # Episode thumbnail. The detail modal's episode list reads role:thumb
    # images via DetailPanel.image_url/2. When TMDB has a still_path, we
    # download from there (mirrors the pipeline FetchMetadata stage).
    # When it doesn't — the shipped showcase catalog is indie/public-
    # domain TV that TMDB mostly lacks stills for — we fall back to a
    # bundled gradient fixture so the TV detail modal still renders a
    # varied strip of thumbs. Regenerate fixtures via
    # `scripts/generate-showcase-thumbs`.
    case ep_data["still_path"] do
      path when is_binary(path) and path != "" ->
        download_image_role!(episode.id, :episode_id, season.tv_series_id, :thumb, path)

      _ ->
        bundle_episode_thumb!(episode)
    end

    episode
  end

  # ---------------------------------------------------------------------------
  # VideoObjects (standalone shorts without TMDB lookups)
  # ---------------------------------------------------------------------------

  defp seed_video_object!(%{title: title} = entry) do
    video_object =
      Library.create_video_object!(%{
        name: title,
        description: entry[:description],
        date_published: entry[:year] && to_string(entry[:year]),
        content_url: entry[:content_url],
        url: entry[:url]
      })

    seed_presence!(video_object.id, :video_object_id, fake_short_path(title))

    video_object
  end

  # ---------------------------------------------------------------------------
  # Watch progress — Continue Watching + completed state
  # ---------------------------------------------------------------------------

  # Drives both HomeLive's Continue Watching row (4 cards + see-all) and
  # the Library `?in_progress=1` deep-link. Six non-completed rows with
  # spread-out progress percentages give the row visibly different
  # progress bars (10–90% spread). Plus a couple of completed entries so
  # the seed isn't all-paused.
  @in_progress_movie_pcts [0.12, 0.28, 0.55, 0.82]
  @in_progress_episode_pcts [0.38, 0.71]
  @completed_movie_count 2
  @completed_episode_count 2

  defp seed_watch_progress!(movies, tv_series) do
    now = DateTime.utc_now()
    movies_with_id = Enum.filter(movies, & &1.id)

    episodes_with_id =
      tv_series
      |> Enum.filter(& &1.id)
      |> Enum.flat_map(& &1.seasons)
      |> Enum.flat_map(& &1.episodes)
      |> Enum.filter(& &1.id)

    in_progress_movies =
      seed_movie_progress(Enum.take(movies_with_id, length(@in_progress_movie_pcts)),
        pcts: @in_progress_movie_pcts,
        completed: false,
        now: now,
        stagger_offset: 0
      )

    completed_movies =
      movies_with_id
      |> Enum.drop(length(@in_progress_movie_pcts))
      |> Enum.take(@completed_movie_count)
      |> seed_movie_progress(
        pcts: List.duplicate(1.0, @completed_movie_count),
        completed: true,
        now: now,
        stagger_offset: length(@in_progress_movie_pcts)
      )

    in_progress_episodes =
      seed_episode_progress(Enum.take(episodes_with_id, length(@in_progress_episode_pcts)),
        pcts: @in_progress_episode_pcts,
        completed: false,
        now: now,
        stagger_offset: 0
      )

    completed_episodes =
      episodes_with_id
      |> Enum.drop(length(@in_progress_episode_pcts))
      |> Enum.take(@completed_episode_count)
      |> seed_episode_progress(
        pcts: List.duplicate(1.0, @completed_episode_count),
        completed: true,
        now: now,
        stagger_offset: length(@in_progress_episode_pcts)
      )

    in_progress_movies + completed_movies + in_progress_episodes + completed_episodes
  end

  defp seed_movie_progress(movies, opts) do
    now = Keyword.fetch!(opts, :now)
    pcts = Keyword.fetch!(opts, :pcts)
    completed? = Keyword.fetch!(opts, :completed)
    stagger_offset = Keyword.fetch!(opts, :stagger_offset)
    duration = 5400.0

    movies
    |> Enum.zip(pcts)
    |> Enum.with_index()
    |> Enum.map(fn {{movie, pct}, idx} ->
      {:ok, _} =
        Library.find_or_create_watch_progress_for_movie(%{
          movie_id: movie.id,
          position_seconds: pct * duration,
          duration_seconds: duration,
          completed: completed?,
          last_watched_at: DateTime.add(now, -(stagger_offset + idx) * 3600, :second)
        })

      :ok
    end)
    |> length()
  end

  defp seed_episode_progress(episodes, opts) do
    now = Keyword.fetch!(opts, :now)
    pcts = Keyword.fetch!(opts, :pcts)
    completed? = Keyword.fetch!(opts, :completed)
    stagger_offset = Keyword.fetch!(opts, :stagger_offset)
    duration = 1800.0

    episodes
    |> Enum.zip(pcts)
    |> Enum.with_index()
    |> Enum.map(fn {{episode, pct}, idx} ->
      {:ok, _} =
        Library.find_or_create_watch_progress_for_episode(%{
          episode_id: episode.id,
          position_seconds: pct * duration,
          duration_seconds: duration,
          completed: completed?,
          last_watched_at: DateTime.add(now, -(stagger_offset + idx) * 900, :second)
        })

      :ok
    end)
    |> length()
  end

  # ---------------------------------------------------------------------------
  # Release tracking — upcoming + available-now
  # ---------------------------------------------------------------------------

  defp seed_release_tracking!(client) do
    # Public-domain and CC-licensed titles only — the showcase is a
    # legally-safe demo, so even metadata references stick to PD/CC.
    # All five titles already live in the showcase library; tracking
    # them here models the "watch for restorations / new seasons" flow
    # without referencing copyrighted properties.
    upcoming = [
      {:movie, "Big Buck Bunny"},
      {:movie, "Sintel"},
      {:movie, "Nosferatu"},
      {:tv_series, "The Beverly Hillbillies"},
      {:tv_series, "Pioneer One"}
    ]

    count =
      Enum.reduce(upcoming, 0, fn {media_type, title}, acc ->
        case track_upcoming(client, media_type, title) do
          :ok -> acc + 1
          _ -> acc
        end
      end)

    sprinkle_calendar_releases!()
    count
  end

  # Real TMDB-sourced release dates land wherever the real world puts
  # them — usually months into the future, so the current-month
  # calendar view ends up mostly empty. For the screenshot, sprinkle
  # synthetic Release rows across the current month so the calendar
  # shows thumbnails on multiple days the way it would for a user
  # whose tracked shows are actively airing.
  #
  # Only TV series get sprinkled — movies already have meaningful real
  # theatrical/digital dates from TMDB, and adding synthetic rows on
  # top makes the same movie show up 3-4 times in the Now Available /
  # Upcoming lists.
  defp sprinkle_calendar_releases! do
    items = Enum.filter(ReleaseTracking.list_all_items(), &(&1.media_type == :tv_series))

    if items == [] do
      :ok
    else
      today = Date.utc_today()
      last_day = Date.days_in_month(today)

      # Eight evenly-spaced days across the month so the calendar
      # reads as "lots happening" without clustering.
      days = Enum.filter([3, 8, 12, 16, 19, 22, 26, 29], &(&1 <= last_day))

      items
      |> Stream.cycle()
      |> Enum.zip(days)
      |> Enum.each(fn {item, day} ->
        date = Date.new!(today.year, today.month, day)
        released = Date.compare(date, today) != :gt

        {season_number, episode_number} =
          case item.media_type do
            :tv_series -> {5, day}
            _ -> {nil, nil}
          end

        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: date,
          title: calendar_release_title(item, season_number, episode_number),
          season_number: season_number,
          episode_number: episode_number,
          released: released,
          in_library: false
        })
      end)

      :ok
    end
  end

  defp calendar_release_title(%{media_type: :tv_series, name: name}, season, episode) do
    "#{name} · S#{season}E#{episode}"
  end

  defp calendar_release_title(%{media_type: :movie, name: name}, _season, _episode) do
    name
  end

  defp track_upcoming(client, :movie, title) do
    case TMDB.Client.search_movie(title, nil, client) do
      {:ok, [%{"id" => id, "title" => name} | _]} ->
        case ReleaseTracking.track_from_search(%{tmdb_id: id, media_type: :movie, name: name}) do
          {:ok, _item} -> :ok
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp track_upcoming(client, :tv_series, title) do
    case TMDB.Client.search_tv(title, nil, client) do
      {:ok, [%{"id" => id, "name" => name} | _]} ->
        case ReleaseTracking.track_from_search(%{tmdb_id: id, media_type: :tv_series, name: name}) do
          {:ok, _item} -> :ok
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # ---------------------------------------------------------------------------
  # Pending review files
  # ---------------------------------------------------------------------------

  defp seed_pending_files!(client) do
    client
    |> pending_file_data()
    |> Enum.map(&Review.find_or_create_pending_file!/1)
    |> length()
  end

  # ---------------------------------------------------------------------------
  # Watch history events
  # ---------------------------------------------------------------------------

  # Heavy-Rotation rewatches (≥2 events per entity) plus a long tail of
  # single events distributed across the last 90 days. Drives:
  #
  #   - HomeLive Heavy Rotation row — `WatchHistory.top_rewatches(min: 2)`
  #     returns ≥8 entities so the 8-up poster grid fills with `Nx` badges.
  #   - History page — populated heatmap colour ramp (a busy day with 4+
  #     completions for the deepest cell), a multi-day current-week
  #     streak, and ≥80 events overall so stats read as 3-digit hours.
  #   - Type-filter chips — at least one episode event so the Episodes
  #     filter has content (Videos remains intentionally empty).
  defp seed_watch_history!(movies, tv_series) do
    now = DateTime.utc_now(:second)
    movies_with_id = Enum.filter(movies, & &1.id)

    episodes_with_id =
      tv_series
      |> Enum.filter(& &1.id)
      |> Enum.flat_map(& &1.seasons)
      |> Enum.flat_map(& &1.episodes)
      |> Enum.filter(& &1.id)

    rewatch_events = seed_rewatch_events!(movies_with_id, episodes_with_id, now)
    long_tail_events = seed_long_tail_events!(movies_with_id, episodes_with_id, now)
    streak_events = seed_streak_events!(movies_with_id, now)
    busy_day_events = seed_busy_day_events!(movies_with_id, episodes_with_id, now)

    rewatch_events + long_tail_events + streak_events + busy_day_events
  end

  # Heavy Rotation candidates — 8 entities (6 movies + 2 episodes) with
  # 4..10 events each. Counts vary so the `Nx` badges read as a real
  # rewatch distribution rather than every card showing "2×". Higher
  # ends (10×) are realistic for short-form content (Blender open
  # movies are ~10 min — comfortable to rewatch on a loop).
  @heavy_rotation_movie_counts [10, 8, 6, 5, 4, 4]
  @heavy_rotation_episode_counts [5, 4]

  defp seed_rewatch_events!(movies, episodes, now) do
    movie_count =
      movies
      |> Enum.zip(@heavy_rotation_movie_counts)
      |> Enum.flat_map(fn {movie, count} ->
        for event_idx <- 0..(count - 1) do
          create_movie_event!(
            movie,
            DateTime.add(now, -(7 + event_idx * 9) * 86_400, :second),
            5400.0 + event_idx * 60
          )
        end
      end)
      |> length()

    episode_count =
      episodes
      |> Enum.zip(@heavy_rotation_episode_counts)
      |> Enum.flat_map(fn {episode, count} ->
        for event_idx <- 0..(count - 1) do
          create_episode_event!(
            episode,
            DateTime.add(now, -(10 + event_idx * 11) * 86_400, :second),
            1800.0
          )
        end
      end)
      |> length()

    movie_count + episode_count
  end

  # Long tail — every remaining movie + remaining episodes get 3 events
  # each. Combined with heavy-rotation rewatches the seed comfortably
  # clears 80 events spread across many distinct days.
  defp seed_long_tail_events!(movies, episodes, now) do
    tail_movies = Enum.drop(movies, length(@heavy_rotation_movie_counts))
    tail_episodes = Enum.drop(episodes, length(@heavy_rotation_episode_counts))

    movie_count =
      tail_movies
      |> Enum.with_index()
      |> Enum.flat_map(fn {movie, movie_idx} ->
        for event_idx <- 0..2 do
          day_offset = 14 + movie_idx * 5 + event_idx * 13
          create_movie_event!(movie, DateTime.add(now, -day_offset * 86_400, :second), 5400.0)
        end
      end)
      |> length()

    episode_count =
      tail_episodes
      |> Enum.with_index()
      |> Enum.flat_map(fn {episode, episode_idx} ->
        for event_idx <- 0..2 do
          day_offset = 22 + episode_idx * 7 + event_idx * 17
          create_episode_event!(episode, DateTime.add(now, -day_offset * 86_400, :second), 1800.0)
        end
      end)
      |> length()

    movie_count + episode_count
  end

  # Five consecutive days of activity ending today so the History page's
  # Current Streak stat reads as multi-day.
  defp seed_streak_events!(movies, now) do
    streak_movies = Enum.take(movies, 5)

    streak_movies
    |> Enum.with_index()
    |> Enum.map(fn {movie, day_offset} ->
      create_movie_event!(movie, DateTime.add(now, -day_offset * 86_400, :second), 5400.0)
      :ok
    end)
    |> length()
  end

  # One day with 5 completions so the heatmap renders its deepest-green
  # colour ramp step.
  defp seed_busy_day_events!(movies, episodes, now) do
    busy_day = DateTime.add(now, -42 * 86_400, :second)
    pool = Enum.take(movies, 4) ++ Enum.take(episodes, 1)

    pool
    |> Enum.with_index()
    |> Enum.map(fn {entity, slot_idx} ->
      stamp = DateTime.add(busy_day, -slot_idx * 1800, :second)

      case entity do
        %Library.Movie{} = movie -> create_movie_event!(movie, stamp, 5400.0)
        %Library.Episode{} = episode -> create_episode_event!(episode, stamp, 1800.0)
      end
    end)
    |> length()
  end

  defp create_movie_event!(movie, completed_at, duration_seconds) do
    {:ok, event} =
      WatchHistory.create_event(%{
        entity_type: :movie,
        movie_id: movie.id,
        title: movie.name,
        duration_seconds: duration_seconds,
        completed_at: completed_at
      })

    event
  end

  defp create_episode_event!(episode, completed_at, duration_seconds) do
    {:ok, event} =
      WatchHistory.create_event(%{
        entity_type: :episode,
        episode_id: episode.id,
        title: episode.name,
        duration_seconds: duration_seconds,
        completed_at: completed_at
      })

    event
  end

  # ---------------------------------------------------------------------------
  # Acquisition activity — Coming Up grab badges + Activity filter variety
  # ---------------------------------------------------------------------------

  # Drives:
  #
  #   - HomeLive "Coming Up This Week" + UpcomingLive Coming Up section —
  #     four releases scheduled within the next seven days, each tied to
  #     a grab in a *different* status so all four badge variants render
  #     side-by-side: Grabbed, Searching, Pending (snoozed), Scheduled
  #     (no grab row).
  #   - /download Activity tab — at least one grab per status filter chip
  #     (`searching`, `grabbed`, `snoozed`, `abandoned`, `cancelled`),
  #     mixing `auto` and `manual` origin.
  #
  # Returns the total grab count for the seed summary.
  defp seed_acquisition_activity! do
    seed_coming_up_grabs!()
    seed_extra_activity_grabs!()
    Repo.aggregate(Grab, :count)
  end

  # Coming-Up badge states. Order matters only insofar as each tracked TV
  # item gets one slot: a Grabbed badge today+1, Searching today+2,
  # Pending today+4, Scheduled today+6. The Scheduled slot deliberately
  # has *no* grab row — its "Scheduled" variant comes from the absence
  # of a matching grab in `Acquisition.statuses_for_releases/1`.
  @coming_up_slots [
    {1, "grabbed", "auto"},
    {2, "searching", "auto"},
    {4, "snoozed", "auto"},
    {6, nil, nil}
  ]

  defp seed_coming_up_grabs! do
    today = Date.utc_today()
    tv_items = Enum.filter(ReleaseTracking.list_all_items(), &(&1.media_type == :tv_series))

    if tv_items == [] do
      :ok
    else
      tv_items
      |> Stream.cycle()
      |> Enum.zip(@coming_up_slots)
      |> Enum.with_index()
      |> Enum.each(fn {{item, {day_offset, status, origin}}, slot_idx} ->
        air_date = Date.add(today, day_offset)
        season_number = 6
        episode_number = 11 + slot_idx

        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: air_date,
          title: "#{item.name} · S#{season_number}E#{episode_number}",
          season_number: season_number,
          episode_number: episode_number,
          released: false,
          in_library: false
        })

        if status do
          insert_grab!(%{
            tmdb_id: to_string(item.tmdb_id),
            tmdb_type: to_string(item.media_type),
            title: "#{item.name} S#{season_number}E#{episode_number}",
            season_number: season_number,
            episode_number: episode_number,
            origin: origin,
            status: status
          })
        end
      end)

      :ok
    end
  end

  # The Activity tab needs every status chip populated. Coming-Up
  # already covers searching / grabbed / snoozed; here we add abandoned
  # and cancelled, plus one manual-origin grab so the activity feed
  # shows a mix of auto vs user-initiated work.
  defp seed_extra_activity_grabs! do
    insert_grab!(%{
      tmdb_id: "showcase-manual-1",
      tmdb_type: "manual",
      title: "Phantom of the Opera (1925) · 1080p WEB-DL",
      origin: "manual",
      status: "grabbed",
      prowlarr_guid: "showcase-manual-1",
      manual_query: "Phantom of the Opera 1925"
    })

    insert_grab!(%{
      tmdb_id: "showcase-abandoned-1",
      tmdb_type: "movie",
      title: "Carnival of Souls (1962)",
      origin: "auto",
      status: "abandoned",
      attempt_count: 5
    })

    insert_grab!(%{
      tmdb_id: "showcase-cancelled-1",
      tmdb_type: "movie",
      title: "Plan 9 from Outer Space (1959)",
      origin: "auto",
      status: "cancelled",
      cancelled_reason: "user_cancelled"
    })
  end

  # Inserts a Grab in any status. The public Grab.create_changeset only
  # casts a subset of fields and defaults `status` to "searching", so the
  # seed bypasses it via `Ecto.Changeset.change/2` to land each row
  # directly in the desired terminal/intermediate state. Real production
  # transitions still flow through the dedicated changesets
  # (`grabbed_changeset`, `attempt_changeset`, etc.) elsewhere.
  defp insert_grab!(attrs) do
    now = DateTime.utc_now(:second)
    base = Map.merge(%{inserted_at: now, updated_at: now}, attrs)

    base =
      case attrs[:status] do
        "grabbed" -> Map.put_new(base, :grabbed_at, now)
        "abandoned" -> Map.put_new(base, :cancelled_at, now)
        "cancelled" -> Map.put_new(base, :cancelled_at, now)
        _ -> base
      end

    %Grab{}
    |> Ecto.Changeset.change(base)
    |> Repo.insert!()
  end

  # Fake Prowlarr + download-client configuration and a recorded "ok"
  # test result so `/download` renders instead of redirecting to `/`.
  # Real integrations would still fail at runtime (the URLs don't point
  # anywhere), but the UI renders the search form + empty queue card
  # which is what the screenshot needs.
  defp seed_fake_capabilities! do
    MediaCentarr.Config.update(:prowlarr_url, "http://localhost:9696")
    MediaCentarr.Config.update(:prowlarr_api_key, "showcase-prowlarr-key")
    MediaCentarr.Config.update(:download_client_type, "qbittorrent")
    MediaCentarr.Config.update(:download_client_url, "http://localhost:8080")
    MediaCentarr.Config.update(:download_client_username, "admin")
    MediaCentarr.Config.update(:download_client_password, "showcase-dl-password")

    MediaCentarr.Capabilities.save_test_result(:prowlarr, :ok)
    MediaCentarr.Capabilities.save_test_result(:download_client, :ok)
    MediaCentarr.Capabilities.save_test_result(:tmdb, :ok)

    # Flip the showcase-mode flag and invalidate the HTTP clients so
    # subsequent Prowlarr / qBittorrent calls go through the fixture
    # plugs in MediaCentarr.Showcase.Stubs instead of hitting real
    # backends that the showcase instance doesn't have.
    MediaCentarr.Config.update(:showcase_mode, true)
    MediaCentarr.Acquisition.Prowlarr.invalidate_client()
    MediaCentarr.Acquisition.DownloadClient.QBittorrent.invalidate_client()

    :ok
  end

  # Synthetic log entries so the /console page has varied content at
  # screenshot time. Touches every non-framework component once at each
  # level. Framework components (:phoenix, :ecto, :live_view) are filled
  # naturally by the server accepting HTTP requests during the tour.
  defp seed_console_entries! do
    Log.info(:watcher, "scanned 14 files in /showcase/media")
    Log.info(:pipeline, "processed 3 movies, 1 TV series, 2 extras in last batch")
    Log.info(:tmdb, "search hit: Nosferatu (1922) → TMDB 653")
    Log.info(:library, "linked watched file: Big Buck Bunny (2008).mkv")
    Log.info(:playback, "session stopped: position 1820s of 5400s")

    Log.warning(:tmdb, "rate limit window: 3 requests queued, backing off 250ms")

    Log.warning(
      :watcher,
      "file appeared then disappeared within debounce window: /showcase/tmp/.partial.mkv"
    )

    Log.warning(
      :pipeline,
      "no confident TMDB match for 'Ambiguous-RELEASE-GROUP.mkv' — escalated to review queue"
    )

    Log.error(:library, "image download failed for backdrop (404) — falling back to poster crop")

    :ok
  end

  defp search_movie(title, year, client) do
    case TMDB.Client.search_movie(title, year, client) do
      {:ok, [%{"id" => id} | _]} -> {:ok, id}
      {:ok, []} -> {:error, :not_found}
      {:ok, _} -> {:error, :unexpected_shape}
      {:error, _} = err -> err
    end
  end

  defp search_tv(title, year, client) do
    case TMDB.Client.search_tv(title, year, client) do
      {:ok, [%{"id" => id} | _]} -> {:ok, id}
      {:ok, []} -> {:error, :not_found}
      {:ok, _} -> {:error, :unexpected_shape}
      {:error, _} = err -> err
    end
  end

  defp download_images!(entity_id, tmdb_data, fk) do
    poster_path = tmdb_data["poster_path"]
    backdrop_path = tmdb_data["backdrop_path"]

    download_image_role!(entity_id, fk, entity_id, :poster, poster_path)
    download_image_role!(entity_id, fk, entity_id, :backdrop, backdrop_path)

    :ok
  end

  defp download_image_role!(_owner_id, _fk, _entity_id, _role, nil), do: :ok
  defp download_image_role!(_owner_id, _fk, _entity_id, _role, ""), do: :ok

  # Always writes a `pipeline_image_queue` row (carrying the TMDB CDN URL)
  # before attempting the inline download. If the inline download fails,
  # the queue row remains `:pending` and the Settings → Library
  # Maintenance → Repair button can drain it later via
  # `Pipeline.ImageRepair.repair_all/0`.
  defp download_image_role!(owner_id, fk, entity_id, role, path) do
    url = "https://image.tmdb.org/t/p/original#{path}"
    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []
    primary = List.first(watch_dirs)

    if primary do
      extension = path |> Path.extname() |> String.trim_leading(".") |> String.downcase()
      extension = if extension == "", do: "jpg", else: extension

      enqueue_for_repair(owner_id, fk, entity_id, role, url, primary)
      perform_inline_download(owner_id, fk, role, extension, url, primary)
    else
      :ok
    end
  end

  defp enqueue_for_repair(owner_id, fk, entity_id, role, url, watch_dir) do
    {:ok, _entry} =
      MediaCentarr.Pipeline.ImageQueue.create(%{
        owner_id: owner_id,
        owner_type: owner_type_for(fk),
        role: to_string(role),
        source_url: url,
        entity_id: entity_id,
        watch_dir: watch_dir,
        status: "pending",
        retry_count: 0
      })

    :ok
  end

  defp owner_type_for(:movie_id), do: "movie"
  defp owner_type_for(:tv_series_id), do: "tv_series"
  defp owner_type_for(:movie_series_id), do: "movie_series"
  defp owner_type_for(:video_object_id), do: "video_object"
  defp owner_type_for(:episode_id), do: "episode"

  defp perform_inline_download(owner_id, fk, role, extension, url, watch_dir) do
    images_root = MediaCentarr.Config.images_dir_for(watch_dir)
    dest = Path.join([images_root, owner_id, "#{role}.#{extension}"])

    case MediaCentarr.Images.download(url, dest, []) do
      {:ok, _} ->
        Library.create_image!(%{
          fk => owner_id,
          :role => to_string(role),
          :content_url => "#{owner_id}/#{role}.#{extension}",
          :extension => extension
        })

        mark_queue_complete(owner_id, role)
        :ok

      {:error, _category, reason} ->
        # The queue row stays :pending so Repair can drain it later. We
        # log and move on — failing the whole seed on a single image is
        # worse than letting the operator click Repair afterwards.
        Log.warning(
          :library,
          "showcase: image download failed for #{owner_id}/#{role}: #{inspect(reason)} — left in queue for repair"
        )

        :ok
    end
  end

  defp mark_queue_complete(owner_id, role) do
    import Ecto.Query

    role_str = to_string(role)

    MediaCentarr.Repo.update_all(
      from(e in MediaCentarr.Pipeline.ImageQueueEntry,
        where: e.owner_id == ^owner_id and e.role == ^role_str
      ),
      set: [status: "complete", updated_at: DateTime.utc_now(:second)]
    )
  end

  @bundled_thumb_count 5

  # Fallback for episodes TMDB has no still_path for (Pioneer One, Dragnet
  # 1951, etc.). Copies a bundled gradient fixture from
  # priv/showcase/fixtures/thumbs/thumb-N.jpg into the episode's image
  # directory and creates the matching role=thumb Image row. Picks a
  # fixture by (episode_number - 1) mod count so consecutive episodes
  # get different colors. Regenerate the fixtures via
  # `scripts/generate-showcase-thumbs`.
  defp bundle_episode_thumb!(episode) do
    fixture_index = rem(max(episode.episode_number - 1, 0), @bundled_thumb_count) + 1
    fixture = Path.expand("priv/showcase/fixtures/thumbs/thumb-#{fixture_index}.jpg")

    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

    with primary when is_binary(primary) <- List.first(watch_dirs),
         true <- File.exists?(fixture) do
      images_root = MediaCentarr.Config.images_dir_for(primary)
      dest = Path.join([images_root, episode.id, "thumb.jpg"])
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(fixture, dest)

      Library.create_image!(%{
        episode_id: episode.id,
        role: "thumb",
        content_url: "#{episode.id}/thumb.jpg",
        extension: "jpg"
      })

      :ok
    else
      _ -> :ok
    end
  end

  defp extract_genre_names(nil), do: []
  defp extract_genre_names(genres) when is_list(genres), do: Enum.map(genres, & &1["name"])

  defp minutes_to_iso(nil), do: nil
  defp minutes_to_iso(0), do: nil
  defp minutes_to_iso(minutes) when is_integer(minutes), do: "PT#{minutes}M"

  defp fake_episode_path(series_name, season_number, episode_number) do
    safe_name = String.replace(series_name, ~r/[^a-zA-Z0-9]+/, ".")
    season_str = season_number |> Integer.to_string() |> String.pad_leading(2, "0")
    episode_str = episode_number |> Integer.to_string() |> String.pad_leading(2, "0")

    Path.join(
      showcase_watch_dir(),
      "#{safe_name}/Season #{season_number}/#{safe_name}.S#{season_str}E#{episode_str}.mkv"
    )
  end

  defp fake_movie_path(title) do
    safe_name = String.replace(title, ~r/[^a-zA-Z0-9]+/, ".")
    Path.join(showcase_watch_dir(), "#{safe_name}.mkv")
  end

  defp fake_short_path(title) do
    safe_name = String.replace(title, ~r/[^a-zA-Z0-9]+/, ".")
    Path.join(showcase_watch_dir(), "shorts/#{safe_name}.mkv")
  end

  defp showcase_watch_dir do
    case MediaCentarr.Config.get(:watch_dirs) do
      [dir | _] -> dir
      _ -> "/showcase"
    end
  end

  # Locate which season an episode belongs to by walking the seasons list.
  # Seeded series have at most a handful of seasons, so this is fine.
  defp episode_season_number(episode, seasons) do
    Enum.find_value(seasons, 1, fn season ->
      if Enum.any?(season.episodes, &(&1.id == episode.id)), do: season.season_number
    end)
  end

  # Seeds one file-presence pair (library_watched_files + watcher_files) so
  # the entity satisfies `Library.Browser.fetch_all_typed_entries`'s filter
  # requiring a present watched file. Also touches an empty stub file at
  # `file_path` so the detail modal's "video missing" banner doesn't fire
  # — the UI checks File.exists?/1 on the content path for that state, and
  # the showcase can't ship real video files. If the user drops a real
  # file at that path later, mpv plays it; if not, the stub at least
  # makes the detail screenshots look like a populated library.
  # Both helpers are idempotent (Library.link_file and
  # FilePresence.record_file use get_by + upsert; File.touch! is a no-op
  # on existing files).
  defp seed_presence!(entity_id, fk_column, file_path) do
    watch_dir = showcase_watch_dir()

    attrs = Map.put(%{file_path: file_path, watch_dir: watch_dir}, fk_column, entity_id)

    Library.link_file!(attrs)
    FilePresence.record_file(file_path, watch_dir)

    File.mkdir_p!(Path.dirname(file_path))
    File.touch!(file_path)

    :ok
  end

  # Belt-and-suspenders: the Mix task wrapper refuses to run without
  # MEDIA_CENTARR_CONFIG_OVERRIDE, but a direct IEx call to this function
  # would bypass that check. This rail fires for both invocation paths by
  # inspecting the live config.
  defp assert_showcase_db! do
    db_path = MediaCentarr.Config.get(:database_path) || ""

    if !String.contains?(db_path, "showcase") do
      raise """
      Showcase seeder refusing to seed: database_path=#{inspect(db_path)}
      doesn't look like a showcase DB.

      The showcase seeder only runs against a DB whose configured path
      contains "showcase". Set MEDIA_CENTARR_CONFIG_OVERRIDE to
      defaults/media-centarr-showcase.toml (or a custom TOML with a
      showcase-prefixed database_path) and try again.
      """
    end
  end

  defp pending_file_data(client) do
    # Real TMDB poster paths for public-domain films not in the showcase
    # catalog, so the "pending review" state is internally consistent
    # (these aren't already in the library) and the review UI renders
    # real artwork instead of broken-image boxes.
    stranger_46 = tmdb_poster_path(client, "The Stranger", 1946)
    his_girl_friday = tmdb_poster_path(client, "His Girl Friday", 1940)
    detour = tmdb_poster_path(client, "Detour", 1945)
    doa = tmdb_poster_path(client, "D.O.A.", 1949)

    [
      %{
        file_path: "/showcase/tv/Uncharted.Series.S01E01.mkv",
        watch_directory: "/showcase/tv",
        parsed_title: "Uncharted Series",
        parsed_year: 2025,
        parsed_type: "tv",
        season_number: 1,
        episode_number: 1,
        tmdb_id: nil,
        confidence: nil,
        candidates: []
      },
      # Multi-match scenario: parser saw "The Stranger" with no year;
      # TMDB has several films that plausibly match.
      %{
        file_path: "/showcase/movies/The.Stranger.mkv",
        watch_directory: "/showcase/movies",
        parsed_title: "The Stranger",
        parsed_year: nil,
        parsed_type: "movie",
        tmdb_id: nil,
        confidence: nil,
        candidates: [
          %{
            "tmdb_id" => 9400,
            "title" => "The Stranger",
            "year" => "1946",
            "confidence" => 0.82,
            "poster_path" => stranger_46
          },
          %{
            "tmdb_id" => 41_631,
            "title" => "His Girl Friday",
            "year" => "1940",
            "confidence" => 0.75,
            "poster_path" => his_girl_friday
          }
        ]
      },
      # Low-confidence match: clean filename but the parser's heuristic
      # isn't confident enough to auto-approve.
      %{
        file_path: "/showcase/movies/Detour.1945.mkv",
        watch_directory: "/showcase/movies",
        parsed_title: "Detour",
        parsed_year: 1945,
        parsed_type: "movie",
        tmdb_id: 25_660,
        confidence: 0.58,
        match_title: "Detour",
        match_year: "1945",
        match_poster_path: detour
      },
      # Mismatch / scene-group noise: parser latched onto an unrelated
      # film with very low confidence.
      %{
        file_path: "/showcase/movies/Ambiguous-RELEASE-GROUP.mkv",
        watch_directory: "/showcase/movies",
        parsed_title: "Ambiguous",
        parsed_type: nil,
        tmdb_id: 4330,
        confidence: 0.21,
        match_title: "D.O.A.",
        match_year: "1949",
        match_poster_path: doa
      }
    ]
  end

  defp tmdb_poster_path(client, title, year) do
    case TMDB.Client.search_movie(title, year, client) do
      {:ok, [%{"poster_path" => path} | _]} when is_binary(path) -> path
      _ -> nil
    end
  end
end
