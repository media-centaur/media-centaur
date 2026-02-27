defmodule MediaManager.Pipeline.Producer do
  @moduledoc """
  GenStage producer that subscribes to PubSub for pipeline input events.

  Receives `{:file_detected, %{path, watch_dir}}` and
  `{:review_resolved, %{path, watch_dir, tmdb_id, tmdb_type, pending_file_id}}`
  messages via PubSub on the `"pipeline:input"` topic, converts them to
  `%Payload{}` structs, and dispatches to Broadway processors on demand.
  """
  use GenStage
  require MediaManager.Log, as: Log

  alias MediaManager.Pipeline.Payload

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "pipeline:input")
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    state = %{state | demand: state.demand + incoming_demand}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  @impl true
  def handle_info({:file_detected, %{path: path, watch_dir: watch_dir}}, state) do
    payload = build_payload(:file_detected, %{path: path, watch_dir: watch_dir})

    Log.info(:pipeline, "producer received file_detected: #{Path.basename(path)}")

    state = %{state | queue: :queue.in(payload, state.queue)}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  def handle_info(
        {:review_resolved,
         %{
           path: path,
           watch_dir: watch_dir,
           tmdb_id: tmdb_id,
           tmdb_type: tmdb_type,
           pending_file_id: pending_file_id
         }},
        state
      ) do
    payload =
      build_payload(:review_resolved, %{
        path: path,
        watch_dir: watch_dir,
        tmdb_id: tmdb_id,
        tmdb_type: tmdb_type,
        pending_file_id: pending_file_id
      })

    Log.info(:pipeline, "producer received review_resolved: #{Path.basename(path)}")

    state = %{state | queue: :queue.in(payload, state.queue)}
    {messages, state} = dispatch(state)
    {:noreply, messages, state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  @doc """
  Builds a `%Payload{}` from a PubSub event.

  Exposed as a public function for testing.
  """
  @spec build_payload(atom(), map()) :: Payload.t()
  def build_payload(:file_detected, %{path: path, watch_dir: watch_dir}) do
    %Payload{
      file_path: path,
      watch_directory: watch_dir,
      entry_point: :file_detected
    }
  end

  def build_payload(:review_resolved, %{
        path: path,
        watch_dir: watch_dir,
        tmdb_id: tmdb_id,
        tmdb_type: tmdb_type,
        pending_file_id: pending_file_id
      }) do
    %Payload{
      file_path: path,
      watch_directory: watch_dir,
      entry_point: :review_resolved,
      tmdb_id: tmdb_id,
      tmdb_type: String.to_existing_atom(tmdb_type),
      pending_file_id: pending_file_id
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
end
