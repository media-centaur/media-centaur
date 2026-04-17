defmodule MediaCentarr.Pipeline.Image.Producer do
  @moduledoc """
  GenStage producer for the image pipeline.

  Subscribes to `MediaCentarr.Topics.pipeline_images()` PubSub topic, receives
  `{:images_pending, %{entity_id: uuid, watch_dir: string}}` messages,
  queries the `pipeline_image_queue` for pending entries for that entity,
  and dispatches one work item per entry.
  """
  use GenStage
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Format
  alias MediaCentarr.Pipeline.ImageQueue

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_images())
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    state = %{state | demand: state.demand + incoming_demand}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  @impl true
  def handle_info({:images_pending, %{entity_id: entity_id, watch_dir: _watch_dir}}, state) do
    Log.info(:pipeline, "queued images — entity #{Format.short_id(entity_id)}")

    work_items = build_work_items(entity_id)

    queue =
      Enum.reduce(work_items, state.queue, fn item, queue ->
        :queue.in(item, queue)
      end)

    state = %{state | queue: queue}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  def handle_info(
        {:enqueue_images, %{entity_id: entity_id, watch_dir: watch_dir, images: images}},
        state
      ) do
    Enum.each(images, fn image ->
      ImageQueue.create(%{
        owner_id: image.owner_id,
        owner_type: image.owner_type,
        role: image.role,
        source_url: image.source_url,
        entity_id: entity_id,
        watch_dir: watch_dir
      })
    end)

    send(self(), {:images_pending, %{entity_id: entity_id, watch_dir: watch_dir}})
    {:noreply, [], state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  # ---------------------------------------------------------------------------
  # Work item building
  # ---------------------------------------------------------------------------

  @doc false
  def build_work_items(entity_id) do
    entries = ImageQueue.list_pending(entity_id)

    items =
      Enum.map(entries, fn entry ->
        %{
          queue_entry: entry,
          owner_id: entry.owner_id,
          entity_id: entry.entity_id,
          watch_dir: entry.watch_dir
        }
      end)

    if items != [] do
      Log.info(
        :pipeline,
        "queued #{length(items)} images — entity #{Format.short_id(entity_id)}"
      )
    end

    items
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
      [:media_centarr, :image_pipeline, :queue_depth],
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
