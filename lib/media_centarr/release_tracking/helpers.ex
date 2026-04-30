defmodule MediaCentarr.ReleaseTracking.Helpers do
  @moduledoc """
  Shared helper functions used by Scanner and Refresher.
  """

  import Ecto.Query
  alias MediaCentarr.Repo

  @doc """
  Finds the highest season/episode pair for a TV series in the library.
  Returns `{season_number, episode_number}` or `{0, 0}` if none found.
  """
  def find_last_library_episode(nil), do: {0, 0}

  def find_last_library_episode(library_entity_id) do
    result =
      Repo.one(
        from(e in MediaCentarr.Library.Episode,
          join: s in MediaCentarr.Library.Season,
          on: e.season_id == s.id,
          where: s.tv_series_id == ^library_entity_id,
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

    seasons = [max(last_season, 1)]
    seasons = if next_season > hd(seasons), do: seasons ++ [next_season], else: seasons
    Enum.uniq(seasons)
  end

  @doc """
  Fetch upcoming releases for a TV series from TMDB.
  Tries season-level extraction first, falls back to next_episode_to_air.
  """
  def fetch_tv_releases(tmdb_id, last_season, last_episode, response) do
    alias MediaCentarr.TMDB.Client
    alias MediaCentarr.ReleaseTracking.Extractor

    seasons = seasons_to_fetch(response, last_season)

    releases =
      seasons
      |> Enum.flat_map(fn season_num ->
        case Client.get_season(tmdb_id, season_num) do
          {:ok, season_data} ->
            Extractor.extract_episodes_since(season_data, last_season, last_episode)

          {:error, _} ->
            []
        end
      end)
      |> mark_released()

    if releases == [] do
      mark_released(Extractor.extract_tv_releases(response))
    else
      releases
    end
  end

  @doc """
  Fetch upcoming releases for a movie collection from TMDB.
  """
  def fetch_collection_releases(response) do
    alias MediaCentarr.ReleaseTracking.Extractor

    normalize_collection_releases(Extractor.extract_collection_releases(response))
  end

  @doc """
  Fetch a single release row from a TMDB `/movie/{id}` response. Used by
  the solo-movie tracking fallback (when `/collection/{id}` 404s the
  refresher tries `/movie/{id}` and the response shape is a single movie
  rather than a list of `parts`).
  """
  def fetch_movie_releases(response) do
    alias MediaCentarr.ReleaseTracking.Extractor

    response
    |> Extractor.extract_movie_release_dates()
    |> Enum.map(fn release ->
      %{
        air_date: release.air_date,
        title: release.title,
        season_number: nil,
        episode_number: nil
      }
    end)
    |> mark_released()
  end

  @doc """
  Sets `:released` flag on each release based on whether `air_date` is today or earlier.
  """
  def mark_released(releases) do
    today = Date.utc_today()

    Enum.map(releases, fn release ->
      aired = release.air_date != nil && Date.compare(release.air_date, today) != :gt
      Map.put(release, :released, aired)
    end)
  end

  @doc """
  Normalizes collection releases (from Extractor) into the standard release
  shape with nil season/episode, then marks released status.
  """
  def normalize_collection_releases(releases) do
    releases
    |> Enum.map(fn release ->
      %{air_date: release.air_date, title: release.title, season_number: nil, episode_number: nil}
    end)
    |> mark_released()
  end
end
