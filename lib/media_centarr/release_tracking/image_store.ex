defmodule MediaCentarr.ReleaseTracking.ImageStore do
  @moduledoc """
  Downloads and manages images for tracked items via the shared `Images` service.
  Stores to `data/images/tracking/{tmdb_id}/`.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Images

  @tmdb_poster_url "https://image.tmdb.org/t/p/w185"
  @tmdb_backdrop_url "https://image.tmdb.org/t/p/w300"
  @tracking_images_dir "data/images/tracking"

  def download_poster(tmdb_id, tmdb_path),
    do: download_role(tmdb_id, tmdb_path, :poster, @tmdb_poster_url, "poster.jpg")

  def download_backdrop(tmdb_id, tmdb_path),
    do: download_role(tmdb_id, tmdb_path, :backdrop, @tmdb_backdrop_url, "backdrop.jpg")

  defp download_role(_tmdb_id, nil, _role, _url_prefix, _filename), do: {:ok, nil}

  defp download_role(tmdb_id, tmdb_path, role, url_prefix, filename) when is_binary(tmdb_path) do
    url = url_prefix <> tmdb_path
    dest = image_path(tmdb_id, filename)

    case Images.download_raw(url, dest) do
      {:ok, _path} ->
        Log.info(:library, "downloaded tracking #{role} for tmdb_id=#{tmdb_id}")
        {:ok, relative_path(dest)}

      {:error, _category, _reason} ->
        {:ok, nil}
    end
  end

  defp image_path(tmdb_id, filename) do
    Path.join([@tracking_images_dir, to_string(tmdb_id), filename])
  end

  defp relative_path(path), do: Path.relative_to(path, "data")
end
