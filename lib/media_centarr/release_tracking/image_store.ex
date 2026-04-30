defmodule MediaCentarr.ReleaseTracking.ImageStore do
  @moduledoc """
  Downloads and manages images for tracked items via the shared `Images` service.

  Files are stored under `<data_dir>/images/tracking/{tmdb_id}/`, where
  `data_dir` comes from `MediaCentarr.Config.get(:data_dir)` (defaults to
  the SQLite database's parent directory — typically
  `~/.local/share/media-centarr/`).

  The DB stores the path *relative* to `data_dir` —
  e.g. `images/tracking/124101/backdrop.jpg`. `MediaCentarrWeb.Plugs.ImageServer`
  joins that relative path back against the same `data_dir` at request time,
  so writers and readers stay in sync regardless of cwd.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Config
  alias MediaCentarr.Images

  # TMDB serves at multiple fixed widths — `w185`/`w300` were originally
  # picked to match the now-replaced thumbnail-sized tracking UI. The
  # current card layout renders backdrops at full-card width (~400-600px
  # on desktop), where w300 visibly upscales. Match the rest of the
  # codebase (mapper.ex, pipeline/image_repair.ex, showcase.ex) and use
  # `original`. Storage cost is trivial — one file per tracked item.
  @tmdb_poster_url "https://image.tmdb.org/t/p/original"
  @tmdb_backdrop_url "https://image.tmdb.org/t/p/original"
  @tracking_subdir "images/tracking"

  # Files written before the switch to `original` were typically
  # 10-20KB w300/w185 thumbnails. TMDB `original` backdrops/posters
  # land in the 80KB-500KB+ range, so 50KB cleanly separates the two.
  @stale_threshold_bytes 50_000

  def download_poster(tmdb_id, tmdb_path),
    do: download_role(tmdb_id, tmdb_path, :poster, @tmdb_poster_url, "poster.jpg")

  def download_backdrop(tmdb_id, tmdb_path),
    do: download_role(tmdb_id, tmdb_path, :backdrop, @tmdb_backdrop_url, "backdrop.jpg")

  @doc """
  Returns true if `path` is missing, empty, or under
  `#{@stale_threshold_bytes}` bytes — the size class of legacy
  `w300`/`w185` thumbnails fetched before the switch to `original`.
  """
  @spec stale_image?(String.t()) :: boolean
  def stale_image?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size < @stale_threshold_bytes
      {:error, _} -> true
    end
  end

  @doc """
  Returns the on-disk absolute path for a given role on a tmdb_id, even
  if the file does not yet exist. Useful for staleness checks that do
  not need a TMDB lookup.
  """
  @spec on_disk_path(:backdrop | :poster, integer()) :: String.t()
  def on_disk_path(:backdrop, tmdb_id), do: absolute_image_path(tmdb_id, "backdrop.jpg")
  def on_disk_path(:poster, tmdb_id), do: absolute_image_path(tmdb_id, "poster.jpg")

  @doc """
  Re-downloads a tracking image only if the on-disk copy is stale per
  `stale_image?/1`. Pass `nil` for `tmdb_path` and the call no-ops with
  `:skipped` (no source URL to refetch from).

  Returns `:refreshed` after a successful re-download, `:current` when
  the file was already a healthy size, `:failed` when the download
  errored, or `:skipped` when there was nothing to do.
  """
  @spec refresh_if_stale(:backdrop | :poster, integer(), String.t() | nil) ::
          :refreshed | :current | :failed | :skipped
  def refresh_if_stale(_role, _tmdb_id, nil), do: :skipped

  def refresh_if_stale(role, tmdb_id, tmdb_path)
      when role in [:backdrop, :poster] and is_binary(tmdb_path) do
    {filename, downloader} =
      case role do
        :backdrop -> {"backdrop.jpg", &download_backdrop/2}
        :poster -> {"poster.jpg", &download_poster/2}
      end

    dest = absolute_image_path(tmdb_id, filename)

    if stale_image?(dest) do
      case downloader.(tmdb_id, tmdb_path) do
        {:ok, path} when is_binary(path) -> :refreshed
        _ -> :failed
      end
    else
      :current
    end
  end

  defp download_role(_tmdb_id, nil, _role, _url_prefix, _filename), do: {:ok, nil}

  defp download_role(tmdb_id, tmdb_path, role, url_prefix, filename) when is_binary(tmdb_path) do
    url = url_prefix <> tmdb_path
    dest = absolute_image_path(tmdb_id, filename)

    case Images.download_raw(url, dest) do
      {:ok, _path} ->
        Log.info(:library, "downloaded tracking #{role} for tmdb_id=#{tmdb_id}")
        {:ok, relative_image_path(tmdb_id, filename)}

      {:error, _category, _reason} ->
        {:ok, nil}
    end
  end

  defp absolute_image_path(tmdb_id, filename) do
    Path.join([data_dir(), @tracking_subdir, to_string(tmdb_id), filename])
  end

  defp relative_image_path(tmdb_id, filename) do
    Path.join([@tracking_subdir, to_string(tmdb_id), filename])
  end

  # Falls back to "data" (cwd-relative) only if data_dir is not configured —
  # mirrors the legacy behaviour so a misconfigured deploy still writes
  # somewhere instead of crashing.
  defp data_dir, do: Config.get(:data_dir) || "data"
end
