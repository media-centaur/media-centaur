defmodule MediaCentaur.ImagePipeline.RetryScheduler do
  @moduledoc """
  Automatically retries transient image download failures with exponential backoff.

  Queries `pipeline_image_queue` for entries with status `failed`, applies
  exponential backoff based on `retry_count` and `updated_at`, and gives up
  after 5 attempts by marking the entry as `permanent`.

  All retry state lives in the database — the GenServer itself is stateless,
  running a simple tick loop every 2 minutes.

  ## Backoff

  `min(2^count * 30_000, 300_000)` ms — 30s, 1m, 2m, 4m, 5m cap.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.ImageQueue

  @retry_interval_ms 2 * 60 * 1_000
  @max_retries 5

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    process_pending()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Core logic
  # ---------------------------------------------------------------------------

  defp process_pending do
    entries = ImageQueue.list_retryable()

    if entries == [] do
      :ok
    else
      now = DateTime.utc_now()

      {exhausted, retryable} =
        Enum.split_with(entries, fn entry ->
          entry.retry_count >= @max_retries
        end)

      # Mark exhausted entries as permanent
      Enum.each(exhausted, fn entry ->
        Log.info(
          :pipeline,
          "retry scheduler: giving up on #{entry.role} for #{entry.owner_id} after #{entry.retry_count} attempts"
        )

        ImageQueue.update_status(entry, :permanent)
      end)

      # Filter retryable entries by backoff elapsed
      ready =
        Enum.filter(retryable, fn entry ->
          backoff = backoff_ms(entry.retry_count)
          elapsed = DateTime.diff(now, entry.updated_at, :millisecond)
          elapsed >= backoff
        end)

      # Reset to pending and broadcast per entity
      if ready != [] do
        Enum.each(ready, fn entry ->
          ImageQueue.reset_to_pending(entry)
        end)

        ready
        |> Enum.uniq_by(fn entry -> entry.entity_id end)
        |> Enum.each(fn entry ->
          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            MediaCentaur.Topics.pipeline_images(),
            {:images_pending, %{entity_id: entry.entity_id, watch_dir: entry.watch_dir}}
          )
        end)
      end
    end
  end

  defp backoff_ms(count) do
    min(Integer.pow(2, count) * 30_000, 300_000)
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @retry_interval_ms)
  end
end
