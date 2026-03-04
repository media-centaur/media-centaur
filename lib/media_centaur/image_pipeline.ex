defmodule MediaCentaur.ImagePipeline do
  @moduledoc """
  Broadway pipeline that downloads and resizes images asynchronously.

  Listens for `{:images_pending, %{entity_id, watch_dir}}` events on the
  `"pipeline:images"` PubSub topic, queries pending Image records (url set,
  content_url nil), downloads from TMDB CDN, resizes to spec, writes to disk,
  and updates Image records with the local content_url.

  Broadway config: 1 producer (PubSub subscriber), 4 processors (moderate
  concurrency to avoid hammering TMDB CDN), 1 batcher (collects entity IDs
  for broadcast).
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.Pipeline.ImageProcessor

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {MediaCentaur.ImagePipeline.Producer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: 4]],
      batchers: [default: [concurrency: 1, batch_size: 20, batch_timeout: 5_000]]
    )
  end

  @impl true
  def handle_message(:default, message, _context) do
    %{image: image, owner_id: owner_id, entity_id: entity_id, watch_dir: watch_dir} =
      message.data

    extension = ImageProcessor.output_extension(image.role)
    relative_path = "#{owner_id}/#{image.role}.#{extension}"
    images_dir = MediaCentaur.Config.images_dir_for(watch_dir)
    dest_path = Path.join(images_dir, relative_path)

    telemetry_metadata = %{role: image.role, entity_id: entity_id}
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:media_centaur, :image_pipeline, :download, :start],
      %{system_time: System.system_time()},
      telemetry_metadata
    )

    case ImageProcessor.download_and_resize(image.url, image.role, dest_path) do
      :ok ->
        duration = System.monotonic_time() - start_time
        Log.info(:pipeline, "image downloaded: #{relative_path}")

        :telemetry.execute(
          [:media_centaur, :image_pipeline, :download, :stop],
          %{duration: duration},
          Map.merge(telemetry_metadata, %{result: :ok})
        )

        message
        |> Broadway.Message.update_data(fn data ->
          Map.merge(data, %{relative_path: relative_path, extension: extension})
        end)

      {:error, category, reason} ->
        duration = System.monotonic_time() - start_time

        Log.warning(
          :pipeline,
          "image download failed (#{category}) #{image.role} for #{owner_id}: #{inspect(reason)}"
        )

        :telemetry.execute(
          [:media_centaur, :image_pipeline, :download, :stop],
          %{duration: duration},
          Map.merge(telemetry_metadata, %{result: :error, error_reason: inspect(reason)})
        )

        Broadway.Message.failed(message, {category, reason})
    end
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    Enum.each(messages, fn message ->
      %{image: image, relative_path: relative_path, extension: extension} = message.data

      Library.update_image!(image, %{content_url: relative_path, extension: extension})
    end)

    entity_ids =
      messages
      |> MapSet.new(fn message -> message.data.entity_id end)
      |> MapSet.delete(nil)
      |> MapSet.to_list()

    if entity_ids != [] do
      Log.info(
        :pipeline,
        "image batch complete, broadcasting #{length(entity_ids)} entity changes"
      )

      Helpers.broadcast_entities_changed(entity_ids)
    end

    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn
      %{status: {:failed, {category, reason}}, data: %{image: image, owner_id: owner_id}} ->
        Log.warning(
          :pipeline,
          "image failed (#{category}): #{image.role} for #{owner_id} — #{inspect(reason)}"
        )

        case category do
          :permanent ->
            Ash.destroy!(image)

          :transient ->
            if GenServer.whereis(MediaCentaur.ImagePipeline.RetryScheduler) do
              MediaCentaur.ImagePipeline.RetryScheduler.record_failure(image.id)
            end
        end

      _ ->
        :ok
    end)

    messages
  end
end
