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

  def download_poster(tmdb_id, tmdb_path) when is_binary(tmdb_path) do
    url = @tmdb_poster_url <> tmdb_path
    dest = image_path(tmdb_id, "poster.jpg")

    case Images.download_raw(url, dest) do
      {:ok, _path} ->
        Log.info(:library, "downloaded tracking poster for tmdb_id=#{tmdb_id}")
        {:ok, relative_path(dest)}

      {:error, _category, _reason} ->
        {:ok, nil}
    end
  end

  def download_poster(_tmdb_id, nil), do: {:ok, nil}

  def download_backdrop(tmdb_id, tmdb_path) when is_binary(tmdb_path) do
    url = @tmdb_backdrop_url <> tmdb_path
    dest = image_path(tmdb_id, "backdrop.jpg")

    case Images.download_raw(url, dest) do
      {:ok, _path} ->
        Log.info(:library, "downloaded tracking backdrop for tmdb_id=#{tmdb_id}")
        {:ok, relative_path(dest)}

      {:error, _category, _reason} ->
        {:ok, nil}
    end
  end

  def download_backdrop(_tmdb_id, nil), do: {:ok, nil}

  defp image_path(tmdb_id, filename) do
    Path.join([@tracking_images_dir, to_string(tmdb_id), filename])
  end

  defp relative_path(path), do: Path.relative_to(path, "data")
end
