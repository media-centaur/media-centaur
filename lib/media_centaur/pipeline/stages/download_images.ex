defmodule MediaCentaur.Pipeline.Stages.DownloadImages do
  @moduledoc """
  Pipeline stage 4: downloads images from TMDB CDN to a temporary staging
  directory. Does NOT update any database records — just downloads files and
  records their local paths in the payload's `staged_images` list.

  The Library Ingress (Phase 2) will move staged images to permanent storage
  and create Image records.

  Individual image download failures are logged as warnings but do not fail
  the stage.
  """
  require Logger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.Payload

  @spec run(Payload.t()) :: {:ok, Payload.t()}
  def run(%Payload{metadata: metadata} = payload) do
    staging_dir = create_staging_dir()

    entity_images = download_images(metadata.images, staging_dir, "entity")

    child_movie_images =
      if metadata[:child_movie] do
        download_images(metadata.child_movie.images, staging_dir, "child_movie")
      else
        []
      end

    episode_images =
      if metadata[:season] && metadata.season[:episode] do
        download_images(metadata.season.episode.images, staging_dir, "episode")
      else
        []
      end

    staged = entity_images ++ child_movie_images ++ episode_images

    Log.info(:pipeline, "downloaded #{length(staged)} images to staging")

    {:ok, %{payload | staged_images: staged}}
  end

  defp download_images(images, staging_dir, owner_tag) when is_list(images) do
    Enum.flat_map(images, fn image ->
      case download_image(image, staging_dir, owner_tag) do
        {:ok, staged} -> [staged]
        {:error, _reason} -> []
      end
    end)
  end

  defp download_images(_, _staging_dir, _owner_tag), do: []

  defp download_image(image, staging_dir, owner_tag) do
    extension = image[:extension] || "jpg"
    filename = "#{owner_tag}_#{image.role}.#{extension}"
    local_path = Path.join(staging_dir, filename)

    case image_downloader().download(image.url, local_path) do
      :ok ->
        {:ok, %{role: image.role, owner: owner_tag, local_path: local_path}}

      {:error, reason} ->
        Logger.warning("DownloadImages: failed #{owner_tag}/#{image.role}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp create_staging_dir do
    unique_id = Ash.UUID.generate()
    dir = Path.join([System.tmp_dir!(), "media_centaur_staging", unique_id])
    File.mkdir_p!(dir)
    dir
  end

  defp image_downloader do
    Application.get_env(:media_centaur, :staging_image_downloader, __MODULE__.HttpDownloader)
  end

  # ---------------------------------------------------------------------------
  # Default HTTP downloader
  # ---------------------------------------------------------------------------

  defmodule HttpDownloader do
    @moduledoc false

    def download(url, local_path) do
      local_path |> Path.dirname() |> File.mkdir_p!()

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          File.write(local_path, body)

        {:ok, %{status: status}} ->
          {:error, {:http_error, status, url}}

        {:error, reason} ->
          {:error, {:download_failed, url, reason}}
      end
    end
  end
end
