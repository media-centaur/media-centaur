defmodule MediaManager.Pipeline.ImageDownloader do
  @moduledoc """
  Downloads remote images for a media entity to the local images directory
  and updates each `Image` record with its local `content_url`.

  Only called by the `DownloadImages` pipeline change — this is a pipeline
  implementation detail, not a general-purpose utility.
  """
  require Logger
  require MediaManager.Log, as: Log

  def download_all(entity) do
    images_dir = MediaManager.Config.get(:media_images_dir)

    pending_count =
      length(filter_pending(entity.images)) +
        ((entity.movies || []) |> Enum.flat_map(& &1.images) |> filter_pending() |> length()) +
        ((entity.seasons || [])
         |> Enum.flat_map(fn s -> (s.episodes || []) |> Enum.flat_map(& &1.images) end)
         |> filter_pending()
         |> length())

    Log.info(:pipeline, "#{pending_count} pending images for entity #{entity.id}")

    entity_results = download_pending_images(entity.images, entity.id, images_dir)

    movie_results =
      (entity.movies || [])
      |> Enum.flat_map(fn movie ->
        download_pending_images(movie.images, movie.id, images_dir)
      end)

    episode_results =
      (entity.seasons || [])
      |> Enum.flat_map(fn season ->
        (season.episodes || [])
        |> Enum.flat_map(fn episode ->
          download_pending_images(episode.images, episode.id, images_dir)
        end)
      end)

    all_results = entity_results ++ movie_results ++ episode_results

    # Persist all successful downloads to DB after all HTTP requests complete
    for {:ok, image, relative_path} <- all_results do
      Ash.update!(image, %{content_url: relative_path})
      Logger.info("ImageDownloader: saved #{relative_path}")
    end

    for {:error, role, reason} <- all_results do
      Logger.warning(
        "ImageDownloader: failed #{role} for entity #{entity.id}: #{inspect(reason)}"
      )
    end

    :ok
  end

  defp download_pending_images(images, owner_id, images_dir) do
    images
    |> filter_pending()
    |> Enum.map(fn image ->
      case download_image(image, owner_id, images_dir) do
        {:ok, relative_path} -> {:ok, image, relative_path}
        {:error, reason} -> {:error, image.role, reason}
      end
    end)
  end

  defp filter_pending(images) do
    Enum.filter(images, fn image -> image.url && !image.content_url end)
  end

  defp download_image(image, entity_id, images_dir) do
    relative_path = "#{entity_id}/#{image.role}.#{image.extension}"
    absolute_path = Path.join(images_dir, relative_path)

    absolute_path |> Path.dirname() |> File.mkdir_p!()

    case Req.get(image.url) do
      {:ok, %{status: 200, body: body}} ->
        case File.write(absolute_path, body) do
          :ok ->
            {:ok, relative_path}

          {:error, reason} ->
            Logger.error("ImageDownloader: write failed for #{relative_path}: #{inspect(reason)}")

            {:error, {:write_failed, relative_path, reason}}
        end

      {:ok, %{status: status}} ->
        Logger.warning("ImageDownloader: HTTP #{status} for #{image.url}")
        {:error, {:http_error, status, image.url}}

      {:error, reason} ->
        Logger.error("ImageDownloader: request failed for #{image.url}: #{inspect(reason)}")
        {:error, {:download_failed, image.url, reason}}
    end
  end
end
