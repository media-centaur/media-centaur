defmodule MediaCentaur.ImagePipeline do
  @moduledoc """
  Broadway pipeline that downloads and resizes images asynchronously.

  Listens for `{:images_pending, %{entity_id, watch_dir}}` events on the
  `"pipeline:images"` PubSub topic, queries pending queue entries,
  downloads from TMDB CDN, resizes to spec, writes to disk, marks queue
  entries complete, and broadcasts `{:image_ready, ...}` on the
  `"pipeline:publish"` topic for `Library.Inbound` to create Image records.

  Broadway config: 1 producer (PubSub subscriber), 4 processors (moderate
  concurrency to avoid hammering TMDB CDN), 1 batcher (collects entity IDs
  for broadcast).
  """
  use Broadway
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.Pipeline.{ImageQueue, ImageProcessor}
  alias MediaCentaur.Topics

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
    %{queue_entry: entry, owner_id: owner_id, entity_id: entity_id, watch_dir: watch_dir} =
      message.data

    extension = ImageProcessor.output_extension(entry.role)
    relative_path = "#{owner_id}/#{entry.role}.#{extension}"
    images_dir = MediaCentaur.Config.images_dir_for(watch_dir)
    dest_path = Path.join(images_dir, relative_path)

    telemetry_metadata = %{role: entry.role, entity_id: entity_id}
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:media_centaur, :image_pipeline, :download, :start],
      %{system_time: System.system_time()},
      telemetry_metadata
    )

    case ImageProcessor.download_and_resize(entry.source_url, entry.role, dest_path) do
      :ok ->
        duration = System.monotonic_time() - start_time
        Log.info(:pipeline, "downloaded image — #{relative_path}")

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
          "image download failed (#{category}) #{entry.role} for #{owner_id}: #{inspect(reason)}"
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
      %{
        queue_entry: entry,
        relative_path: relative_path,
        extension: extension,
        owner_id: owner_id,
        entity_id: entity_id
      } = message.data

      ImageQueue.update_status(entry, :complete)

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.pipeline_publish(),
        {:image_ready,
         %{
           owner_id: owner_id,
           owner_type: entry.owner_type,
           role: entry.role,
           content_url: relative_path,
           extension: extension,
           entity_id: entity_id
         }}
      )
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
    {permanent, transient} =
      messages
      |> Enum.filter(&match?(%{status: {:failed, _}}, &1))
      |> Enum.split_with(fn %{status: {:failed, {category, _}}} -> category == :permanent end)

    Enum.each(permanent ++ transient, fn
      %{status: {:failed, {category, reason}}, data: %{owner_id: owner_id, queue_entry: entry}} ->
        Log.warning(
          :pipeline,
          "image failed (#{category}): #{entry.role} for #{owner_id} — #{inspect(reason)}"
        )
    end)

    Enum.each(permanent, fn %{data: %{queue_entry: entry}} ->
      ImageQueue.update_status(entry, :permanent)
    end)

    Enum.each(transient, fn %{data: %{queue_entry: entry}} ->
      ImageQueue.mark_failed(entry)
    end)

    messages
  end
end
