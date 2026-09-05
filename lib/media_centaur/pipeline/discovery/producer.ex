defmodule MediaCentaur.Pipeline.Discovery.Producer do
  @moduledoc """
  GenStage producer for the Discovery pipeline.

  Subscribes to `MediaCentaur.Topics.pipeline_input()` for `{:file_detected}`
  events from the Watcher, converts them to `%Payload{}` structs, and dispatches
  to Broadway processors on demand.

  On startup, sends `{:reconcile, 0}` to trigger watcher rescan (ADR-023).
  """
  use GenStage
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.Discovery.InflightSet
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.ProducerQueue

  # `MediaCentaur.Watcher.Supervisor` is a sibling child started later in the
  # same supervision tree (its actual per-directory watchers are started from
  # an async `init_services` Task, not the supervisor's own `start_link`) — so
  # `running?/0` can read `false` for a moment after this producer's `init/1`
  # runs, purely because the watchers haven't been told to start yet. A single
  # unconditional check races that startup ordering and can silently skip
  # reconciliation for the entire session. Retrying briefly closes the race
  # without polling indefinitely: a deliberately-disabled watcher
  # (`services:*:start_watchers` off) exhausts the budget and is skipped
  # exactly as before.
  @max_reconcile_attempts 20
  @reconcile_retry_ms 100

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_input())
    send(self(), {:reconcile, 0})
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @doc false
  def max_reconcile_attempts, do: @max_reconcile_attempts

  @doc """
  Decides what `{:reconcile, attempt}` should do next, given whether the
  watcher currently reports running. Pure — exposed for testing the
  race-retry boundary without spinning up the GenStage process.
  """
  @spec reconcile_action(non_neg_integer(), boolean()) :: :run | {:retry, pos_integer()} | :skip
  def reconcile_action(_attempt, true), do: :run
  def reconcile_action(attempt, false) when attempt >= @max_reconcile_attempts, do: :skip
  def reconcile_action(_attempt, false), do: {:retry, @reconcile_retry_ms}

  @impl true
  def handle_demand(incoming_demand, state) do
    state = %{state | demand: state.demand + incoming_demand}
    {messages, state} = dispatch(state)
    emit_queue_depth(state.queue)
    {:noreply, messages, state}
  end

  @impl true
  def handle_info({:file_detected, %{path: path, media_dir: media_dir}}, state) do
    if InflightSet.claim(path) do
      payload = build_payload(%{path: path, media_dir: media_dir})
      Log.info(:pipeline, "queued #{Path.basename(path)} — file detected")
      state = %{state | queue: :queue.in(payload, state.queue)}
      {messages, state} = dispatch(state)
      emit_queue_depth(state.queue)
      {:noreply, messages, state}
    else
      Log.info(:pipeline, "deduped #{Path.basename(path)} — already in flight")
      {:noreply, [], state}
    end
  end

  # Startup reconciliation (ADR-023): rescan all media directories to re-detect
  # files that were missed while the pipeline was down, and re-emit any files
  # the watcher already knows about but the pipeline never finished ingesting
  # (stranded by a transient TMDB/network failure on a prior run).
  def handle_info({:reconcile, attempt}, state) do
    case reconcile_action(attempt, MediaCentaur.Watcher.Supervisor.running?()) do
      :run ->
        Log.info(:pipeline, "triggered watcher rescan — startup reconciliation")

        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          MediaCentaur.Watcher.Rescan.scan()
          MediaCentaur.Watcher.Rescan.rescan_unlinked()
        end)

      {:retry, delay_ms} ->
        Process.send_after(self(), {:reconcile, attempt + 1}, delay_ms)

      :skip ->
        :ok
    end

    {:noreply, [], state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def ack(:ack_id, successful, failed) do
    Enum.each(successful ++ failed, fn %Broadway.Message{data: %Payload{file_path: path}} ->
      InflightSet.release(path)
    end)

    :ok
  end

  @doc """
  Builds a `%Payload{}` from a file-detected event.

  Exposed as a public function for testing.
  """
  @spec build_payload(map()) :: Payload.t()
  def build_payload(%{path: path, media_dir: media_dir}) do
    %Payload{
      file_path: path,
      media_directory: media_dir
    }
  end

  defp dispatch(%{demand: 0} = state), do: {[], state}

  defp dispatch(state) do
    {payloads, queue, remaining_demand} = ProducerQueue.dequeue(state.queue, state.demand)
    messages = ProducerQueue.to_messages(payloads, __MODULE__)
    {messages, %{state | queue: queue, demand: remaining_demand}}
  end

  defp emit_queue_depth(queue) do
    :telemetry.execute(
      [:media_centaur, :pipeline, :queue_depth],
      %{depth: :queue.len(queue)},
      %{pipeline: :discovery}
    )
  end
end
