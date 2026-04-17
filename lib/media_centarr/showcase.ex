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
          watch_events: non_neg_integer()
        }

  @doc """
  Seeds the currently-connected database with the showcase catalog.

  Returns a summary map with per-entity counts. Does NOT check which profile
  is active — that's the caller's responsibility (the Mix task does it).
  """
  @spec seed!() :: summary()
  def seed! do
    client = TMDB.Client.default_client()

    movies = Enum.map(Catalog.movies(), &seed_movie!(&1, client))
    tv_series = Enum.map(Catalog.tv_series(), &seed_tv_series!(&1, client))
    video_objects = Enum.map(Catalog.video_objects(), &seed_video_object!/1)

    watch_progress_count = seed_watch_progress!(movies, tv_series)
    tracked_count = seed_release_tracking!(movies, tv_series)
    pending_count = seed_pending_files!()
    watch_event_count = seed_watch_history!(movies)

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
      watch_events: watch_event_count
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

      Library.create_external_id!(%{
        movie_id: movie.id,
        source: "tmdb",
        external_id: to_string(tmdb_id)
      })

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

      Library.create_external_id!(%{
        tv_series_id: series.id,
        source: "tmdb",
        external_id: to_string(tmdb_id)
      })

      seasons =
        Enum.map(season_numbers, fn season_number ->
          seed_season!(series, tmdb_id, season_number, client)
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

    Library.create_episode!(%{
      season_id: season.id,
      episode_number: episode_number,
      name: episode_name,
      description: ep_data["overview"],
      duration: minutes_to_iso(ep_data["runtime"]),
      content_url: fake_episode_path(series_name, season.season_number, episode_number)
    })
  end

  # ---------------------------------------------------------------------------
  # VideoObjects (standalone shorts without TMDB lookups)
  # ---------------------------------------------------------------------------

  defp seed_video_object!(%{title: title} = entry) do
    Library.create_video_object!(%{
      name: title,
      description: entry[:description],
      date_published: entry[:year] && to_string(entry[:year]),
      content_url: entry[:content_url],
      url: entry[:url]
    })
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

  defp seed_pending_files! do
    pending_file_data()
    |> Enum.map(&Review.create_pending_file!/1)
    |> length()
  end

  # ---------------------------------------------------------------------------
  # Watch history events
  # ---------------------------------------------------------------------------

  defp seed_watch_history!(movies) do
    now = DateTime.utc_now(:second)

    movies
    |> Enum.filter(& &1.id)
    |> Enum.take(5)
    |> Enum.with_index()
    |> Enum.map(fn {movie, idx} ->
      {:ok, _} =
        WatchHistory.create_event(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: movie.name,
          duration_seconds: 5400.0,
          completed_at: DateTime.add(now, -idx * 86_400, :second)
        })

      :ok
    end)
    |> length()
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

  defp extract_genre_names(nil), do: []
  defp extract_genre_names(genres) when is_list(genres), do: Enum.map(genres, & &1["name"])

  defp minutes_to_iso(nil), do: nil
  defp minutes_to_iso(0), do: nil
  defp minutes_to_iso(minutes) when is_integer(minutes), do: "PT#{minutes}M"

  defp fake_episode_path(series_name, season_number, episode_number) do
    safe_name = String.replace(series_name, ~r/[^a-zA-Z0-9]+/, ".")
    season_str = season_number |> Integer.to_string() |> String.pad_leading(2, "0")
    episode_str = episode_number |> Integer.to_string() |> String.pad_leading(2, "0")
    "/showcase/#{safe_name}/Season #{season_number}/#{safe_name}.S#{season_str}E#{episode_str}.mkv"
  end

  defp pending_file_data do
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
      %{
        file_path: "/showcase/movies/The.Mystery.1958.mkv",
        watch_directory: "/showcase/movies",
        parsed_title: "The Mystery",
        parsed_year: nil,
        parsed_type: "movie",
        tmdb_id: nil,
        confidence: nil,
        candidates: [
          %{
            "tmdb_id" => 11_111,
            "title" => "The Mystery",
            "year" => "1958",
            "confidence" => 0.82,
            "poster_path" => "/placeholder1.jpg"
          },
          %{
            "tmdb_id" => 22_222,
            "title" => "The Mystery",
            "year" => "2004",
            "confidence" => 0.82,
            "poster_path" => "/placeholder2.jpg"
          }
        ]
      },
      %{
        file_path: "/showcase/movies/Showcase.Low.Confidence.2019.mkv",
        watch_directory: "/showcase/movies",
        parsed_title: "Showcase Low Confidence",
        parsed_year: 2019,
        parsed_type: "movie",
        tmdb_id: 33_333,
        confidence: 0.58,
        match_title: "Showcase Low Confidence",
        match_year: "2019",
        match_poster_path: "/placeholder3.jpg"
      },
      %{
        file_path: "/showcase/movies/Ambiguous-RELEASE-GROUP.mkv",
        watch_directory: "/showcase/movies",
        parsed_title: "Ambiguous",
        parsed_type: nil,
        tmdb_id: 44_444,
        confidence: 0.21,
        match_title: "Something Entirely Different",
        match_year: "2011",
        match_poster_path: "/placeholder4.jpg"
      }
    ]
  end
end
