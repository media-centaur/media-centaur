defmodule MediaCentaur.ReleaseTracking.Helpers do
  @moduledoc """
  The artwork side of a tracked title, and two small parsers. What a
  tracked title's calendar *is* lives in `ReleaseTracking.Calendar`, a
  pure function of the stored payloads; this module downloads the
  poster, backdrop and logo those payloads name.
  """

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Extractor
  alias MediaCentaur.TmdbArtwork

  @doc """
  Backfills artwork (poster / backdrop / logo) missing from `item` but
  available in the TMDB `response`, off the caller via `TaskSupervisor`.
  Idempotent — `pending_image_downloads/2` skips roles the item already
  has, so this is safe to call on every onboarding and calendar rebuild.
  """
  def download_images_async(item, tmdb_id, response) do
    if pending_image_downloads(item, response) != [] do
      Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
        download_images_sync(item, tmdb_id, response)
      end)
    end

    :ok
  end

  @doc "Synchronous body of `download_images_async/3`."
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
  crashing.
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
end
