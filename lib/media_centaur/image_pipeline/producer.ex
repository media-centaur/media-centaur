defmodule MediaCentaur.ImagePipeline.Producer do
  @moduledoc """
  GenStage producer for the image pipeline.

  Subscribes to `"pipeline:images"` PubSub topic, receives
  `{:images_pending, %{entity_id: uuid, watch_dir: string}}` messages,
  queries the DB for Image records with `url` set and `content_url` nil
  for that entity (including child movies and episodes), and dispatches
  one work item per image.
  """
  use GenStage
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "pipeline:images")
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    state = %{state | demand: state.demand + incoming_demand}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  @impl true
  def handle_info({:images_pending, %{entity_id: entity_id, watch_dir: watch_dir}}, state) do
    Log.info(:pipeline, "image producer received images_pending for entity #{entity_id}")

    work_items = build_work_items(entity_id, watch_dir)

    queue =
      Enum.reduce(work_items, state.queue, fn item, queue ->
        :queue.in(item, queue)
      end)

    state = %{state | queue: queue}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  # ---------------------------------------------------------------------------
  # Work item building
  # ---------------------------------------------------------------------------

  @doc false
  def build_work_items(entity_id, watch_dir) do
    case Library.get_entity_with_images(entity_id) do
      {:ok, entity} ->
        entity_items = pending_items(entity.images, entity.id, entity_id, watch_dir)

        movie_items =
          (entity.movies || [])
          |> Enum.flat_map(fn movie ->
            pending_items(movie.images, movie.id, entity_id, watch_dir)
          end)

        episode_items =
          (entity.seasons || [])
          |> Enum.flat_map(fn season ->
            (season.episodes || [])
            |> Enum.flat_map(fn episode ->
              pending_items(episode.images, episode.id, entity_id, watch_dir)
            end)
          end)

        items = entity_items ++ movie_items ++ episode_items

        Log.info(
          :pipeline,
          "image producer queued #{length(items)} images for entity #{entity_id}"
        )

        items

      {:error, _} ->
        Log.warning(:pipeline, "image producer: entity #{entity_id} not found")
        []
    end
  end

  defp pending_items(images, owner_id, entity_id, watch_dir) do
    images
    |> Enum.filter(fn image -> image.url && !image.content_url end)
    |> Enum.map(fn image ->
      %{image: image, owner_id: owner_id, entity_id: entity_id, watch_dir: watch_dir}
    end)
  end

  # ---------------------------------------------------------------------------
  # Dispatch
  # ---------------------------------------------------------------------------

  defp dispatch(%{demand: 0} = state), do: {[], state}

  defp dispatch(state) do
    {items, queue, remaining_demand} = dequeue(state.queue, state.demand, [])

    messages =
      Enum.map(items, fn item ->
        %Broadway.Message{data: item, acknowledger: {__MODULE__, :ack_id, :ack_data}}
      end)

    :telemetry.execute(
      [:media_centaur, :image_pipeline, :queue_depth],
      %{depth: :queue.len(queue)},
      %{}
    )

    {messages, %{state | queue: queue, demand: remaining_demand}}
  end

  defp dequeue(queue, 0, acc), do: {Enum.reverse(acc), queue, 0}

  defp dequeue(queue, remaining, acc) do
    case :queue.out(queue) do
      {{:value, item}, queue} -> dequeue(queue, remaining - 1, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue, remaining}
    end
  end
end
