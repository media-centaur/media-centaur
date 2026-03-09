defmodule MediaCentaur.ImagePipeline.RetryScheduler do
  @moduledoc """
  Automatically retries transient image download failures with exponential backoff.

  Replaces the manual "Retry all" / "Dismiss all" buttons from the operations page.
  Queries images with `url != nil AND content_url == nil` every 2 minutes, applies
  per-image retry tracking with exponential backoff, and gives up after 5 attempts
  by destroying the Image record.

  ## State

  In-memory map of `%{image_id => {retry_count, last_attempted_at}}`. On restart
  the state is empty, giving all pending images a fresh round of retries — this
  is desirable since the underlying problem (network, disk, rate limit) may have
  been resolved.

  ## Backoff

  `min(2^count * 30_000, 300_000)` ms — 30s, 1m, 2m, 4m, 5m cap.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library

  @retry_interval_ms 2 * 60 * 1_000
  @max_retries 5

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records a transient download failure for the given image ID.

  The scheduler will retry this image on its next tick, subject to
  exponential backoff and the max retry limit.
  """
  def record_failure(image_id, server \\ __MODULE__) do
    GenServer.cast(server, {:transient_failure, image_id})
  end

  @doc """
  Returns the current retry status: how many images are tracked for retry.
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{retries: %{}}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{retrying_count: map_size(state.retries)}, state}
  end

  @impl true
  def handle_cast({:transient_failure, image_id}, state) do
    now = System.monotonic_time(:millisecond)

    retries =
      Map.update(state.retries, image_id, {1, now}, fn {count, _last} ->
        {count + 1, now}
      end)

    {:noreply, %{state | retries: retries}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    state = process_pending(state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Core logic
  # ---------------------------------------------------------------------------

  defp process_pending(state) do
    pending_images = Library.list_pending_downloads!()

    if pending_images == [] do
      %{state | retries: %{}}
    else
      now = System.monotonic_time(:millisecond)
      pending_ids = MapSet.new(pending_images, & &1.id)

      # Prune state entries for images no longer pending (downloaded or deleted)
      retries = Map.filter(state.retries, fn {id, _} -> MapSet.member?(pending_ids, id) end)

      # Group images by entity for broadcast
      entity_ids_to_broadcast = MapSet.new()

      {retries, entity_ids_to_broadcast, exhausted_images} =
        Enum.reduce(pending_images, {retries, entity_ids_to_broadcast, []}, fn image,
                                                                               {retries_acc,
                                                                                entities_acc,
                                                                                exhausted_acc} ->
          case Map.get(retries_acc, image.id) do
            nil ->
              # First attempt — broadcast immediately
              entities_acc = maybe_add_entity(entities_acc, image)
              {retries_acc, entities_acc, exhausted_acc}

            {count, _last} when count >= @max_retries ->
              # Give up — collect for bulk destroy
              Log.info(
                :pipeline,
                "retry scheduler: giving up on image #{image.id} (#{image.role}) after #{count} attempts"
              )

              retries_acc = Map.delete(retries_acc, image.id)
              entities_acc = maybe_add_entity(entities_acc, image)
              {retries_acc, entities_acc, [image | exhausted_acc]}

            {count, last_attempted} ->
              backoff = backoff_ms(count)

              if now - last_attempted >= backoff do
                # Backoff elapsed — retry
                entities_acc = maybe_add_entity(entities_acc, image)
                {retries_acc, entities_acc, exhausted_acc}
              else
                # Still in backoff — skip
                {retries_acc, entities_acc, exhausted_acc}
              end
          end
        end)

      # Bulk destroy all exhausted images in a single query
      if exhausted_images != [] do
        result =
          Ash.bulk_destroy(exhausted_images, :destroy, %{},
            resource: Library.Image,
            strategy: :stream,
            return_errors?: true
          )

        if result.error_count > 0 do
          Log.warning(
            :pipeline,
            "retry scheduler: bulk destroy errors: #{inspect(result.errors)}"
          )
        end
      end

      # Resolve entity IDs to watch dirs and broadcast
      broadcast_retries(entity_ids_to_broadcast)

      %{state | retries: retries}
    end
  end

  defp maybe_add_entity(entity_ids, image) do
    if image.entity_id do
      MapSet.put(entity_ids, image.entity_id)
    else
      entity_ids
    end
  end

  defp broadcast_retries(entity_ids) do
    if MapSet.size(entity_ids) > 0 do
      ids = MapSet.to_list(entity_ids)

      entities =
        Library.list_entities_with_images!(
          query: [filter: [id: [in: ids]]],
          load: [:watched_files]
        )

      Enum.each(entities, fn entity ->
        case entity.watched_files do
          [first | _] ->
            Phoenix.PubSub.broadcast(
              MediaCentaur.PubSub,
              "pipeline:images",
              {:images_pending, %{entity_id: entity.id, watch_dir: first.watch_dir}}
            )

          _ ->
            :ok
        end
      end)
    end
  end

  defp backoff_ms(count) do
    min(Integer.pow(2, count) * 30_000, 300_000)
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @retry_interval_ms)
  end
end
