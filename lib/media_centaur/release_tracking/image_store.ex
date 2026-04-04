defmodule MediaCentaur.ReleaseTracking.ImageStore do
  @moduledoc """
  Downloads and manages poster images for tracked items.
  Stores to `data/images/tracking/{tmdb_id}/poster.jpg`.
  """

  require MediaCentaur.Log, as: Log

  @base_url "https://image.tmdb.org/t/p/w500"
  @tracking_images_dir "data/images/tracking"

  def download_poster(tmdb_id, tmdb_poster_path) when is_binary(tmdb_poster_path) do
    url = @base_url <> tmdb_poster_path
    dir = Path.join(@tracking_images_dir, to_string(tmdb_id))
    dest = Path.join(dir, "poster.jpg")

    File.mkdir_p!(dir)

    http_client =
      Application.get_env(:media_centaur, :image_http_client, Req)

    result =
      try do
        http_client.get(url)
      rescue
        _ -> {:error, :unavailable}
      end

    case result do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
        File.write!(dest, body)
        Log.info(:library, "downloaded tracking poster for tmdb_id=#{tmdb_id}")
        {:ok, relative_path(dest)}

      {:ok, _response} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :unexpected_response}
    end
  end

  def download_poster(_tmdb_id, nil), do: {:ok, nil}

  def poster_path(tmdb_id) do
    dest = Path.join([@tracking_images_dir, to_string(tmdb_id), "poster.jpg"])
    if File.exists?(dest), do: relative_path(dest), else: nil
  end

  defp relative_path(path), do: Path.relative_to(path, "data")
end
