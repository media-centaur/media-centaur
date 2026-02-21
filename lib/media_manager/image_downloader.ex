defmodule MediaManager.ImageDownloader do
  require Logger

  def download_all(entity) do
    images_dir = MediaManager.Config.get(:media_images_dir)

    entity.images
    |> Enum.filter(fn image -> image.url && !image.content_url end)
    |> Enum.reduce_while(:ok, fn image, :ok ->
      case download_image(image, entity.id, images_dir) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_image(image, entity_id, images_dir) do
    relative_path = "#{entity_id}/#{image.role}.#{image.extension}"
    absolute_path = Path.join(images_dir, relative_path)

    absolute_path |> Path.dirname() |> File.mkdir_p!()

    case Req.get(image.url) do
      {:ok, %{status: 200, body: body}} ->
        case File.write(absolute_path, body) do
          :ok ->
            Ash.update!(image, %{content_url: relative_path})
            Logger.info("ImageDownloader: saved #{relative_path}")
            :ok

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
