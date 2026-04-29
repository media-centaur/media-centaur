defmodule MediaCentarr.Pipeline.Discovery.Producer do
  @moduledoc """
  GenStage producer for the Discovery pipeline.

  Subscribes to `MediaCentarr.Topics.pipeline_input()` for `{:file_detected}`
  events from the Watcher, converts them to `%Payload{}` structs, and dispatches
  to Broadway processors on demand.

  On startup, sends `:reconcile` to trigger watcher rescan (ADR-023).
  """
  use GenStage
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Pipeline.Payload

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_input())
    send(self(), :reconcile)
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    state = %{state | demand: state.demand + incoming_demand}
    {messages, state} = dispatch(state)
    emit_queue_depth(state.queue)
    {:noreply, messages, state}
  end

  @impl true
  def handle_info({:file_detected, %{path: path, watch_dir: watch_dir}}, state) do
    payload = build_payload(%{path: path, watch_dir: watch_dir})

    Log.info(:pipeline, "queued #{Path.basename(path)} — file detected")

    state = %{state | queue: :queue.in(payload, state.queue)}
    {messages, state} = dispatch(state)
    emit_queue_depth(state.queue)
    {:noreply, messages, state}
  end

  # Startup reconciliation (ADR-023): rescan all watch directories to re-detect
  # files that were missed while the pipeline was down, and re-emit any files
  # the watcher already knows about but the pipeline never finished ingesting
  # (stranded by a transient TMDB/network failure on a prior run).
  def handle_info(:reconcile, state) do
    if MediaCentarr.Watcher.Supervisor.running?() do
      Log.info(:pipeline, "triggered watcher rescan — startup reconciliation")

      Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
        MediaCentarr.Watcher.Supervisor.scan()
        MediaCentarr.Watcher.Supervisor.rescan_unlinked()
      end)
    end

    {:noreply, [], state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  @doc """
  Builds a `%Payload{}` from a file-detected event.

  Exposed as a public function for testing.
  """
  @spec build_payload(map()) :: Payload.t()
  def build_payload(%{path: path, watch_dir: watch_dir}) do
    %Payload{
      file_path: path,
      watch_directory: watch_dir
    }
  end

  defp dispatch(%{demand: 0} = state), do: {[], state}

  defp dispatch(state) do
    {payloads, queue, remaining_demand} = dequeue(state.queue, state.demand, [])

    messages =
      Enum.map(payloads, fn payload ->
        %Broadway.Message{data: payload, acknowledger: {__MODULE__, :ack_id, :ack_data}}
      end)

    {messages, %{state | queue: queue, demand: remaining_demand}}
  end

  defp dequeue(queue, 0, acc), do: {Enum.reverse(acc), queue, 0}

  defp dequeue(queue, remaining, acc) do
    case :queue.out(queue) do
      {{:value, payload}, queue} -> dequeue(queue, remaining - 1, [payload | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue, remaining}
    end
  end

  defp emit_queue_depth(queue) do
    :telemetry.execute(
      [:media_centarr, :pipeline, :queue_depth],
      %{depth: :queue.len(queue)},
      %{pipeline: :discovery}
    )
  end
end
