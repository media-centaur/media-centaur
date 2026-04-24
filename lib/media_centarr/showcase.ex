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

  alias MediaCentarr.Library
  alias MediaCentarr.ReleaseTracking
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

    watch_progress_count = seed_watch_progress!(movies, tv_series)
    tracked_count = seed_release_tracking!(movies, tv_series)
    pending_count = seed_pending_files!(client)
    watch_event_count = seed_watch_history!(movies)
    acquisition_count = seed_acquisition!()
    seed_fake_capabilities!()
    seed_console_entries!()

    season_count =
      tv_series
      |> Enum.map(&length(&1.seasons))
      |> Enum.sum()

    episode_count =
      tv_series
      |> Enum.flat_map(& &1.seasons)
      |> Enum.map(&length(&1.episodes))
      |> Enum.sum()

    %{
      movies: length(movies),
      tv_series: length(tv_series),
      seasons: season_count,
      episodes: episode_count,
      video_objects: length(video_objects),
      watch_progress: watch_progress_count,
      tracked_items: tracked_count,
      pending_files: pending_count,
      watch_events: watch_event_count,
      acquisitions: acquisition_count
    }
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
        Log.warning(:library, "showcase: failed to seed movie #{title}: #{inspect(reason)}")
        %{id: nil, name: title}
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
        Log.warning(:library, "showcase: failed to seed tv #{title}: #{inspect(reason)}")
        %{id: nil, name: title, seasons: []}
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
        download_image_role!(episode.id, :episode_id, :thumb, path)

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
  # Watch progress — partial + completed state
  # ---------------------------------------------------------------------------

  defp seed_watch_progress!(movies, tv_series) do
    now = DateTime.utc_now()

    movie_progress =
      movies
      |> Enum.filter(& &1.id)
      |> Enum.take(3)
      |> Enum.with_index()
      |> Enum.map(fn {movie, idx} ->
        # 20%, 60%, completed
        {position, completed} =
          case idx do
            0 -> {0.20 * 5400.0, false}
            1 -> {0.60 * 5400.0, false}
            _ -> {5400.0, true}
          end

        {:ok, _} =
          Library.find_or_create_watch_progress_for_movie(%{
            movie_id: movie.id,
            position_seconds: position,
            duration_seconds: 5400.0,
            completed: completed,
            last_watched_at: DateTime.add(now, -idx * 3600, :second)
          })

        :ok
      end)

    episode_progress =
      tv_series
      |> Enum.filter(& &1.id)
      |> Enum.flat_map(& &1.seasons)
      |> Enum.flat_map(& &1.episodes)
      |> Enum.filter(& &1.id)
      |> Enum.take(4)
      |> Enum.with_index()
      |> Enum.map(fn {episode, idx} ->
        {position, completed} =
          case idx do
            0 -> {0.45 * 1800.0, false}
            _ -> {1800.0, true}
          end

        {:ok, _} =
          Library.find_or_create_watch_progress_for_episode(%{
            episode_id: episode.id,
            position_seconds: position,
            duration_seconds: 1800.0,
            completed: completed,
            last_watched_at: DateTime.add(now, -idx * 900, :second)
          })

        :ok
      end)

    length(movie_progress) + length(episode_progress)
  end

  # ---------------------------------------------------------------------------
  # Release tracking — upcoming + available-now
  # ---------------------------------------------------------------------------

  defp seed_release_tracking!(movies, tv_series) do
    today = Date.utc_today()

    tv_tracked =
      tv_series
      |> Enum.filter(& &1.id)
      |> Enum.take(2)
      |> Enum.map(fn series ->
        item =
          ReleaseTracking.track_item!(%{
            tmdb_id: :rand.uniform(900_000) + 100_000,
            media_type: :tv_series,
            name: series.name,
            library_entity_id: series.id,
            last_refreshed_at: DateTime.utc_now()
          })

        # Upcoming
        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: Date.add(today, 14),
          title: "Next Episode",
          season_number: 2,
          episode_number: 1,
          released: false,
          in_library: false
        })

        # Available now
        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: Date.add(today, -3),
          title: "Recent Episode",
          season_number: 1,
          episode_number: 99,
          released: true,
          in_library: false
        })

        item
      end)

    movie_tracked =
      movies
      |> Enum.filter(& &1.id)
      |> Enum.take(1)
      |> Enum.map(fn movie ->
        ReleaseTracking.track_item!(%{
          tmdb_id: :rand.uniform(900_000) + 100_000,
          media_type: :movie,
          name: movie.name,
          library_entity_id: movie.id,
          last_refreshed_at: DateTime.utc_now()
        })
      end)

    length(tv_tracked) + length(movie_tracked)
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

  defp seed_watch_history!(movies) do
    now = DateTime.utc_now(:second)
    available_movies = movies |> Enum.filter(& &1.id) |> Enum.take(10)

    # Seed 2 watch events per movie, spread across the last 30 days, so
    # the /history page shows a populated, varied feed. Event i for
    # movie j lands at i*day-offset + j*hour-offset so timestamps are
    # distinct and the page renders in chronological order without
    # collisions.
    events =
      for {movie, movie_idx} <- Enum.with_index(available_movies),
          event_idx <- 0..1 do
        day_offset = movie_idx * 2 + event_idx * 5
        hour_offset = movie_idx

        {:ok, _} =
          WatchHistory.create_event(%{
            entity_type: :movie,
            movie_id: movie.id,
            title: movie.name,
            duration_seconds: 5400.0 + movie_idx * 120,
            completed_at:
              now
              |> DateTime.add(-day_offset * 86_400, :second)
              |> DateTime.add(-hour_offset * 3600, :second)
          })

        :ok
      end

    length(events)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # One Acquisition.Grab row in the "searching" state so the /download
  # page's queue monitor card has a visible entry at screenshot time.
  # The Prowlarr client is not called — this is a static DB row only.
  defp seed_acquisition! do
    changeset =
      MediaCentarr.Acquisition.Grab.create_changeset(%{
        tmdb_id: "12345",
        tmdb_type: "movie",
        title: "Showcase Upcoming Film (2026)"
      })

    {:ok, _grab} = MediaCentarr.Repo.insert(changeset)
    1
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

    download_image_role!(entity_id, fk, :poster, poster_path)
    download_image_role!(entity_id, fk, :backdrop, backdrop_path)

    :ok
  end

  defp download_image_role!(_entity_id, _fk, _role, nil), do: :ok
  defp download_image_role!(_entity_id, _fk, _role, ""), do: :ok

  defp download_image_role!(entity_id, fk, role, path) do
    url = "https://image.tmdb.org/t/p/original#{path}"
    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []
    primary = List.first(watch_dirs)

    if primary do
      images_root = MediaCentarr.Config.images_dir_for(primary)
      extension = path |> Path.extname() |> String.trim_leading(".") |> String.downcase()
      extension = if extension == "", do: "jpg", else: extension
      dest = Path.join([images_root, entity_id, "#{role}.#{extension}"])

      case MediaCentarr.Images.download(url, dest, []) do
        {:ok, _} ->
          Library.create_image!(%{
            fk => entity_id,
            :role => to_string(role),
            :content_url => "#{entity_id}/#{role}.#{extension}",
            :extension => extension
          })

          :ok

        {:error, _, _reason} ->
          # Record still gets an Image row with no file — the UI shows a
          # placeholder. Failing the whole seed on image trouble is worse
          # than a missing poster.
          :ok
      end
    else
      :ok
    end
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
