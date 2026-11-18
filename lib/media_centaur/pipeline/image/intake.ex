defmodule MediaCentaur.Pipeline.Image.Intake do
  @moduledoc """
  Turns an import's artwork hand-off into queue rows.

  `Library.Inbound` cannot call into the pipeline, so it publishes a new
  entity's artwork as `{:enqueue_images, %{entity_id, media_dir, images}}`
  on `MediaCentaur.Topics.pipeline_images()`. This process writes those
  rows (`ImageQueue.enqueue/3`) and so runs whether or not artwork
  downloads are on: it sits beside the start flag's children in
  `Pipeline.Image.Supervisor`, not under them. While downloads are off the
  rows wait as `pending`; once on, `Pipeline.Image.RetryScheduler` finds
  them on its next tick. Before this process existed the producer wrote
  the rows, so an import made while downloads were off lost its artwork.
  """
  use GenServer

  alias MediaCentaur.Pipeline.ImageQueue
  alias MediaCentaur.Topics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Topics.subscribe(Topics.pipeline_images())
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        {:enqueue_images, %{entity_id: entity_id, media_dir: media_dir, images: images}},
        state
      ) do
    :ok = ImageQueue.enqueue(entity_id, media_dir, images)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
