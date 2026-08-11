defmodule MediaCentaur.ReleaseTracking.Helpers do
  @moduledoc """
  Shared helper functions used by Scanner and Refresher.
  """

  import Ecto.Query
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Extractor
  alias MediaCentaur.Repo
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
    attrs =
      item
      |> pending_image_downloads(response)
      |> Enum.reduce(%{}, fn {tmdb_path, attr_key, downloader}, acc ->
        case downloader.(item.media_type, tmdb_id, tmdb_path) do
          {:ok, path} when is_binary(path) -> Map.put(acc, attr_key, path)
          _ -> acc
        end
      end)

    if attrs != %{}, do: ReleaseTracking.update_item(item, attrs)
    :ok
  end

  # Returns `[{tmdb_source_path, attr_key, downloader}]` for every image role
  # the item still lacks AND that TMDB has a path for.
  defp pending_image_downloads(item, response) do
    [
      {item.poster_path, Extractor.extract_poster_path(response), :poster_path,
       &TmdbArtwork.download_poster/3},
      {item.backdrop_path, response["backdrop_path"], :backdrop_path, &TmdbArtwork.download_backdrop/3},
      {item.logo_path, Extractor.extract_logo_path(response), :logo_path, &TmdbArtwork.download_logo/3}
    ]
    |> Enum.filter(fn {current, tmdb_path, _, _} -> is_nil(current) and is_binary(tmdb_path) end)
    |> Enum.map(fn {_, tmdb_path, attr_key, downloader} -> {tmdb_path, attr_key, downloader} end)
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
    result =
      Repo.one(
        from(e in MediaCentaur.Library.Episode,
          join: s in MediaCentaur.Library.Season,
          on: e.season_id == s.id,
          where: s.tv_series_id == ^tv_series_id,
          select: {s.season_number, e.episode_number},
          order_by: [desc: s.season_number, desc: e.episode_number],
          limit: 1
        )
      )

    result || {0, 0}
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
  Fetch upcoming releases for a TV series from TMDB.
  Tries season-level extraction first, falls back to next_episode_to_air.
  """
  def fetch_tv_releases(tmdb_id, last_season, last_episode, response) do
    alias MediaCentaur.TMDB.Client
    alias MediaCentaur.ReleaseTracking.Extractor

    seasons = seasons_to_fetch(response, last_season)

    releases =
      Enum.flat_map(seasons, fn season_num ->
        case Client.get_season(tmdb_id, season_num) do
          {:ok, season_data} ->
            Extractor.extract_episodes_since(season_data, last_season, last_episode)

          {:error, _} ->
            []
        end
      end)

    if releases == [] do
      Extractor.extract_tv_releases(response)
    else
      releases
    end
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
