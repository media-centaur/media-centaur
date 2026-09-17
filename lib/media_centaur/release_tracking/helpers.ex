defmodule MediaCentaur.ReleaseTracking.Helpers do
  @moduledoc """
  Shared helper functions used by Scanner and Refresher.
  """

  alias MediaCentaur.ReleaseTracking.Extractor
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbArtwork

  @doc """
  Backfills artwork (poster / backdrop / logo) missing from `item` but
  available in the TMDB `response`, off the caller via `TaskSupervisor`.
  Idempotent — `pending_image_downloads/2` skips roles the item already has,
  so this is safe to call on every scan, refresh, and auto-track. Used by
  both Scanner and Refresher (the single-item fire-and-forget case).
  """
  def download_images_async(item, tmdb_id, response) do
    if pending_image_downloads(item, response) != [] do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        download_images_sync(item, tmdb_id, response)
      end)
    end

    :ok
  end

  @doc """
  Synchronous body of `download_images_async/3`. Called directly by the
  Refresher's Phase-3 `async_stream` so a refresh over N items runs under a
  bounded concurrency rather than fanning out to N independent tasks.
  """
  def download_images_sync(item, tmdb_id, response) do
    landed? =
      item
      |> pending_image_downloads(response)
      |> Enum.map(fn {tmdb_path, downloader} -> downloader.(item.media_type, tmdb_id, tmdb_path) end)
      |> Enum.any?(&match?({:ok, _path}, &1))

    # Landed files change what the UI resolves for this identity — nudge
    # subscribers to re-read.
    if landed?, do: ReleaseTracking.broadcast_releases_updated([item.id])
    :ok
  end

  # Returns `[{tmdb_source_path, downloader}]` for every image role the
  # TmdbArtwork cache still lacks AND that TMDB has a path for — disk is
  # the download ledger, same truth the readers resolve from.
  defp pending_image_downloads(item, response) do
    [
      {:poster, Extractor.extract_poster_path(response), &TmdbArtwork.download_poster/3},
      {:backdrop, response["backdrop_path"], &TmdbArtwork.download_backdrop/3},
      {:logo, Extractor.extract_logo_path(response), &TmdbArtwork.download_logo/3}
    ]
    |> Enum.filter(fn {role, tmdb_path, _downloader} ->
      is_binary(tmdb_path) and
        not File.exists?(TmdbArtwork.on_disk_path(role, item.media_type, item.tmdb_id))
    end)
    |> Enum.map(fn {_role, tmdb_path, downloader} -> {tmdb_path, downloader} end)
  end

  @doc """
  Parses a TMDB id that may arrive as an integer or as a string (the
  `external_id` rows are stored as strings). Returns `{:ok, integer}` or
  `:error` for malformed input, so callers skip the row instead of
  crashing (the Refresher runs this inside `handle_info`).
  """
  @spec parse_tmdb_id(integer() | String.t()) :: {:ok, integer()} | :error
  def parse_tmdb_id(id) when is_integer(id), do: {:ok, id}

  def parse_tmdb_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  @doc """
  Finds the highest season/episode pair for a TV series in the library.
  Returns `{season_number, episode_number}` or `{0, 0}` if none found.
  """
  def find_last_library_episode(nil), do: {0, 0}

  def find_last_library_episode(tv_series_id) do
    MediaCentaur.Library.Episodes.last_season_episode(tv_series_id) || {0, 0}
  end

  @doc """
  Determines which TMDB season numbers to fetch based on the user's last
  library season and the show's next-to-air episode.
  """
  def seasons_to_fetch(response, last_season) do
    total_seasons = response["number_of_seasons"] || 1
    next_ep = response["next_episode_to_air"]
    next_season = if next_ep, do: next_ep["season_number"], else: total_seasons

    base_season = max(last_season, 1)
    next_seasons = if next_season > base_season, do: [next_season], else: []
    Enum.uniq([base_season | next_seasons])
  end

  @doc """
  Fetches a TV series' calendar from TMDB: the releases still to come
  (season-level extraction first, falling back to `next_episode_to_air`)
  and the show's **season sizes** — how many episodes each season has,
  keyed by season-number string, specials excluded — which the drop
  planner hands to every plan as its `span_sizes`, the fit denominator
  (`Acquisition.Plans.Fit`).

  A season whose detail was fetched here is sized by the episodes that
  aired on or before `opts[:today]` (default: today) — the count
  `Targeting.aired_counts/1` produces; every other season takes the
  show detail's `episode_count`, exact for a finished season. No extra
  request: both come from responses this fetch makes anyway.

  Returns `{releases, season_sizes}`.
  """
  @spec fetch_tv_releases(integer(), non_neg_integer(), non_neg_integer(), map(), keyword()) ::
          {[map()], %{String.t() => non_neg_integer()}}
  def fetch_tv_releases(tmdb_id, last_season, last_episode, response, opts \\ []) do
    alias MediaCentaur.TMDB.Client
    alias MediaCentaur.ReleaseTracking.Extractor

    today = Keyword.get_lazy(opts, :today, &Date.utc_today/0)

    # A season detail is only usable with its episode list; anything
    # else (an error, a payload without one) counts as not fetched.
    fetched =
      response
      |> seasons_to_fetch(last_season)
      |> Enum.flat_map(fn season_number ->
        case Client.get_season(tmdb_id, season_number) do
          {:ok, %{"episodes" => episodes} = season_data} when is_list(episodes) ->
            [{season_number, season_data}]

          _not_usable ->
            []
        end
      end)

    releases =
      Enum.flat_map(fetched, fn {_season_number, season_data} ->
        Extractor.extract_episodes_since(season_data, last_season, last_episode)
      end)

    releases = if releases == [], do: Extractor.extract_tv_releases(response), else: releases

    {releases, season_sizes(response, Map.new(fetched), today)}
  end

  # Specials (season 0) are extras, not coverage units — the exclusion
  # `Targeting.aired_counts/1` makes too.
  defp season_sizes(response, fetched_by_number, today) do
    response
    |> Map.get("seasons", [])
    |> Enum.filter(fn season ->
      is_integer(season["season_number"]) and season["season_number"] > 0
    end)
    |> Map.new(fn season ->
      number = season["season_number"]

      size =
        case Map.fetch(fetched_by_number, number) do
          {:ok, season_data} -> aired_count(season_data, today)
          :error -> season["episode_count"] || 0
        end

      {Integer.to_string(number), size}
    end)
  end

  defp aired_count(%{"episodes" => episodes}, today) do
    Enum.count(episodes, fn episode ->
      case MediaCentaur.TMDB.Mapper.parse_date(episode["air_date"]) do
        %Date{} = air_date -> Date.compare(air_date, today) != :gt
        nil -> false
      end
    end)
  end

  @doc """
  Fetch upcoming releases for a movie collection from TMDB.
  """
  def fetch_collection_releases(response) do
    alias MediaCentaur.ReleaseTracking.Extractor

    normalize_collection_releases(Extractor.extract_collection_releases(response))
  end

  @doc """
  Fetch a single release row from a TMDB `/movie/{id}` response. Used by
  the solo-movie tracking fallback (when `/collection/{id}` 404s the
  refresher tries `/movie/{id}` and the response shape is a single movie
  rather than a list of `parts`).
  """
  def fetch_movie_releases(response) do
    alias MediaCentaur.ReleaseTracking.Extractor

    response
    |> Extractor.extract_movie_release_dates()
    |> Enum.map(fn release ->
      %{
        air_date: release.air_date,
        title: release.title,
        release_type: release.release_type,
        part_tmdb_id: response["id"],
        season_number: nil,
        episode_number: nil
      }
    end)
  end

  @doc """
  Normalizes collection releases (from Extractor) into the standard release
  shape with nil season/episode. Keeps the part's own TMDB id — the want
  ledger keys collection-part wants on it.
  """
  def normalize_collection_releases(releases) do
    Enum.map(releases, fn release ->
      %{
        air_date: release.air_date,
        title: release.title,
        part_tmdb_id: release.tmdb_id,
        season_number: nil,
        episode_number: nil
      }
    end)
  end
end
