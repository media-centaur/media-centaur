defmodule MediaCentaur.ReleaseTracking.Acquisition do
  @moduledoc """
  Track-from-search onboarding for release tracking
  (`track_from_search/2`, `track_from_search_async/2`). Title search
  itself lives in `MediaCentaur.TMDB.TitleSearch`.

  Split out of the `ReleaseTracking` context so the CRUD context isn't
  also a search-and-onboard module. Persistence and event creation route
  back through the context (`track_item`, `persist_release!`,
  `create_release!`, `mark_in_library_releases`, `create_event!`,
  `update_item`, `broadcast_releases_updated`), which own those concerns;
  this module owns only the track-from-search flow.
  """

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Extractor, Helpers, Release, Wants}
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.TMDB.Title

  # --- Track from search ---

  @doc """
  Creates a tracking item from a search result. Used by the Track New Show modal.

  Accepts a `MediaCentaur.TMDB.Title` and options:
  - For TV: %{start_season: n, start_episode: n} to set tracking offset
  - For movies: %{} (no options needed)
  """
  @spec track_from_search(Title.t(), map()) :: {:ok, ReleaseTracking.Item.t()} | {:error, term()}
  def track_from_search(%Title{} = title, opts \\ %{}) do
    start_season = Map.get(opts, :start_season, 0)
    start_episode = Map.get(opts, :start_episode, 0)

    case do_track_from_search(title, start_season, start_episode) do
      {:ok, item} ->
        ReleaseTracking.broadcast_releases_updated([item.id])
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fire-and-forget `track_from_search/2`. Runs the (TMDB-fetching) tracking
  on a supervised context-layer task — tracking must complete regardless of
  the triggering LiveView's lifecycle (ADR-049: must-outlive background work
  lives in the context, not a web-layer `start_child`). The resulting
  `broadcast_releases_updated/1` keeps subscribers in sync.
  """
  @spec track_from_search_async(Title.t(), map()) :: :ok
  def track_from_search_async(%Title{} = title, opts \\ %{}) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      track_from_search(title, opts)
    end)

    :ok
  end

  defp do_track_from_search(%Title{media_type: :tv_series} = title, start_season, start_episode) do
    case Client.get_tv(title.tmdb_id) do
      {:ok, response} ->
        all_releases =
          Helpers.fetch_tv_releases(title.tmdb_id, start_season, start_episode, response)

        # "All upcoming" (0,0) = only future episodes. Custom scope = include released too.
        releases =
          if start_season == 0 && start_episode == 0 do
            Enum.reject(all_releases, &Release.released?/1)
          else
            all_releases
          end

        case ReleaseTracking.track_item(%{
               tmdb_id: title.tmdb_id,
               media_type: :tv_series,
               name: response["name"] || title.name,
               source: :manual,
               last_refreshed_at: DateTime.utc_now(),
               last_library_season: start_season,
               last_library_episode: start_episode
             }) do
          {:ok, item} ->
            persist_releases(item, releases)
            create_began_tracking_event(item)
            schedule_image_downloads(item, title.tmdb_id, response)

            {:ok, item}

          {:error, changeset} ->
            {:error, track_item_error(changeset)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_track_from_search(%Title{media_type: :movie} = title, _start_season, _start_episode) do
    case Client.get_movie(title.tmdb_id) do
      {:ok, response} ->
        case ReleaseTracking.track_item(%{
               tmdb_id: title.tmdb_id,
               media_type: :movie,
               name: response["title"] || title.name,
               source: :manual,
               last_refreshed_at: DateTime.utc_now()
             }) do
          {:ok, item} ->
            releases = Extractor.extract_movie_release_dates(response)
            persist_movie_releases(item, releases)

            create_began_tracking_event(item)
            schedule_image_downloads(item, title.tmdb_id, response)

            {:ok, item}

          {:error, changeset} ->
            {:error, track_item_error(changeset)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A duplicate track attempt (double click, stale search results, two
  # in-flight async tracks) hits the {tmdb_id, media_type} unique
  # constraint — an expected no-op, not a fault. Anything else is a
  # genuine changeset failure the caller should see.
  defp track_item_error(changeset) do
    duplicate? =
      Enum.any?(changeset.errors, fn
        {:tmdb_id, {_message, meta}} -> meta[:constraint] == :unique
        _other -> false
      end)

    if duplicate?, do: :already_tracked, else: changeset
  end

  defp persist_releases(item, releases) do
    ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_release!/2)

    ReleaseTracking.mark_in_library_releases(item)
    Wants.sync_item(item)
  end

  defp persist_movie_releases(item, releases) do
    ReleaseTracking.replace_releases!(item, releases, &ReleaseTracking.persist_movie_release!/2)

    Wants.sync_item(item)
  end

  defp create_began_tracking_event(item) do
    ReleaseTracking.create_event!(%{
      item_id: item.id,
      item_name: item.name,
      event_type: :began_tracking,
      description: "Now tracking #{item.name}"
    })
  end

  # NOTE: older 2-image (poster/backdrop) downloader — misses logos and
  # re-fetches existing artwork. Mirrors the Scanner gap that B4 closed via
  # Helpers.download_images_async/3; routing this through that path is a
  # follow-up (it would also drop the post-download broadcast below).
  defp schedule_image_downloads(item, tmdb_id, response) do
    poster_path = Extractor.extract_poster_path(response)
    backdrop_path = response["backdrop_path"]

    if poster_path || backdrop_path do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        downloaded? =
          Enum.any?(
            [
              TmdbArtwork.download_poster(item.media_type, tmdb_id, poster_path),
              TmdbArtwork.download_backdrop(item.media_type, tmdb_id, backdrop_path)
            ],
            fn
              {:ok, path} when is_binary(path) -> true
              _ -> false
            end
          )

        # Landed files change what the UI resolves for this identity —
        # nudge subscribers to re-read.
        if downloaded?, do: ReleaseTracking.broadcast_releases_updated([item.id])
      end)
    end
  end
end
