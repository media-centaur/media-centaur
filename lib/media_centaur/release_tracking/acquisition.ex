defmodule MediaCentaur.ReleaseTracking.Acquisition do
  @moduledoc """
  TMDB-first acquisition for release tracking: omnibox search
  (`search_tmdb/1`) and track-from-search onboarding
  (`track_from_search/2`, `track_from_search_async/2`).

  Split out of the `ReleaseTracking` context so the CRUD context isn't
  also a search-and-onboard module. Persistence and event creation route
  back through the context (`track_item`, `persist_release!`,
  `create_release!`, `mark_in_library_releases`, `create_event!`,
  `update_item`, `broadcast_releases_updated`), which own those concerns;
  this module owns only the TMDB-facing search/track flow.
  """

  import Ecto.Query

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Extractor, Helpers, ImageStore, Item, Release, TitleResult, Wants}
  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.Client

  # --- Search ---

  # A query ending in a standalone year, optionally parenthesized
  # ("Title 1999", "Title (1999)"). The title part must be non-empty —
  # a bare year is a title query ("1999" the film), not a filter.
  @trailing_year_query ~r/^(.+?)\s+\(?((?:19|20)\d{2})\)?$/

  @doc """
  Searches TMDB for movies and TV shows. Plain queries go to the multi
  endpoint, preserving TMDB's cross-type relevance order (a regrouped
  movies-then-tv merge once starved every TV result out of the capped
  omnibox dropdown). Person results are dropped.

  A trailing year ("Title 1999", "Title (1999)") never matches a TMDB
  title through the multi endpoint, so it is stripped and sent as the
  year filter of the per-type search endpoints instead, merged by
  popularity. A year that filters everything out (wrong year, or a
  number that is part of the title) falls back to a year-less multi
  search of the stripped title — the year is a disambiguator, never a
  gatekeeper.

  Returns `[TitleResult.t()]` — the one normalized shape every
  title-search surface consumes.
  """
  @spec search_tmdb(String.t()) :: [TitleResult.t()]
  def search_tmdb(query) do
    results =
      case Regex.run(@trailing_year_query, String.trim(query)) do
        [_full, title, year] -> year_search(title, String.to_integer(year))
        nil -> multi_search(query)
      end

    tracked_tmdb_ids =
      from(i in Item, select: {i.tmdb_id, i.media_type})
      |> Repo.all()
      |> MapSet.new()

    Enum.map(results, fn result ->
      tracked = MapSet.member?(tracked_tmdb_ids, {result.tmdb_id, result.media_type})
      %{result | tracked?: tracked}
    end)
  end

  defp multi_search(query) do
    case Client.search_multi(query) do
      {:ok, results} -> Enum.flat_map(results, &normalize_multi_result/1)
      {:error, _reason} -> []
    end
  end

  # The per-type endpoints carry no cross-type relevance rank, so the
  # merged list orders by TMDB popularity instead.
  defp year_search(title, year) do
    movie_results = tag_media_type(Client.search_movie(title, year), "movie")
    tv_results = tag_media_type(Client.search_tv(title, year), "tv")

    case movie_results ++ tv_results do
      [] ->
        multi_search(title)

      combined ->
        combined
        |> Enum.sort_by(&(&1["popularity"] || 0.0), :desc)
        |> Enum.flat_map(&normalize_multi_result/1)
    end
  end

  defp tag_media_type({:ok, results}, media_type),
    do: Enum.map(results, &Map.put(&1, "media_type", media_type))

  defp tag_media_type({:error, _reason}, _media_type), do: []

  defp normalize_multi_result(%{"media_type" => "movie"} = tmdb), do: [normalize_movie_result(tmdb)]
  defp normalize_multi_result(%{"media_type" => "tv"} = tmdb), do: [normalize_tv_result(tmdb)]
  defp normalize_multi_result(_person_or_unknown), do: []

  defp normalize_movie_result(tmdb) do
    %TitleResult{
      tmdb_id: tmdb["id"],
      media_type: :movie,
      name: tmdb["title"],
      year: extract_year(tmdb["release_date"]),
      release_date: extract_date(tmdb["release_date"]),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: presence(tmdb["overview"])
    }
  end

  defp normalize_tv_result(tmdb) do
    %TitleResult{
      tmdb_id: tmdb["id"],
      media_type: :tv_series,
      name: tmdb["name"],
      year: extract_year(tmdb["first_air_date"]),
      release_date: extract_date(tmdb["first_air_date"]),
      poster_path: tmdb["poster_path"],
      backdrop_path: tmdb["backdrop_path"],
      overview: presence(tmdb["overview"])
    }
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(text) when is_binary(text), do: text

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil
  defp extract_year(<<year::binary-size(4), _::binary>>), do: year

  # Full date, not just the year — the results' upcoming/released scoping
  # compares against today. TMDB leaves unreleased titles undated or with
  # partial strings; both come through as nil.
  defp extract_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp extract_date(_missing), do: nil

  # --- Track from search ---

  @doc """
  Creates a tracking item from a search result. Used by the Track New Show modal.

  Accepts a result map (%{tmdb_id, media_type, name, poster_path}) and options:
  - For TV: %{start_season: n, start_episode: n} to set tracking offset
  - For movies: %{} (no options needed)
  """
  def track_from_search(result, opts \\ %{}) do
    start_season = Map.get(opts, :start_season, 0)
    start_episode = Map.get(opts, :start_episode, 0)

    case do_track_from_search(result, start_season, start_episode) do
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
  def track_from_search_async(result, opts \\ %{}) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      track_from_search(result, opts)
    end)

    :ok
  end

  defp do_track_from_search(%{media_type: :tv_series} = result, start_season, start_episode) do
    case Client.get_tv(result.tmdb_id) do
      {:ok, response} ->
        all_releases =
          Helpers.fetch_tv_releases(result.tmdb_id, start_season, start_episode, response)

        # "All upcoming" (0,0) = only future episodes. Custom scope = include released too.
        releases =
          if start_season == 0 && start_episode == 0 do
            Enum.reject(all_releases, &Release.released?/1)
          else
            all_releases
          end

        {:ok, item} =
          ReleaseTracking.track_item(%{
            tmdb_id: result.tmdb_id,
            media_type: :tv_series,
            name: response["name"] || result.name,
            source: :manual,
            last_refreshed_at: DateTime.utc_now(),
            last_library_season: start_season,
            last_library_episode: start_episode
          })

        persist_releases(item, releases)
        create_began_tracking_event(item)
        schedule_image_downloads(item, result.tmdb_id, response)

        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_track_from_search(%{media_type: :movie} = result, _start_season, _start_episode) do
    case Client.get_movie(result.tmdb_id) do
      {:ok, response} ->
        {:ok, item} =
          ReleaseTracking.track_item(%{
            tmdb_id: result.tmdb_id,
            media_type: :movie,
            name: response["title"] || result.name,
            source: :manual,
            last_refreshed_at: DateTime.utc_now()
          })

        releases = Extractor.extract_movie_release_dates(response)
        persist_movie_releases(item, releases)

        create_began_tracking_event(item)
        schedule_image_downloads(item, result.tmdb_id, response)

        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
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
        attrs = %{}

        attrs =
          case ImageStore.download_poster(tmdb_id, poster_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :poster_path, path)
            _ -> attrs
          end

        attrs =
          case ImageStore.download_backdrop(tmdb_id, backdrop_path) do
            {:ok, path} when is_binary(path) -> Map.put(attrs, :backdrop_path, path)
            _ -> attrs
          end

        if attrs != %{} do
          ReleaseTracking.update_item(item, attrs)
          ReleaseTracking.broadcast_releases_updated([item.id])
        end
      end)
    end
  end
end
