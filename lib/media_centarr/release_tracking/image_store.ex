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

  def download_poster(tmdb_id, tmdb_path),
    do: download_role(tmdb_id, tmdb_path, :poster, @tmdb_poster_url, "poster.jpg")

  def download_backdrop(tmdb_id, tmdb_path),
    do: download_role(tmdb_id, tmdb_path, :backdrop, @tmdb_backdrop_url, "backdrop.jpg")

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
