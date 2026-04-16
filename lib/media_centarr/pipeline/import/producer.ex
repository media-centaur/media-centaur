defmodule MediaCentarr.Pipeline.Import.Producer do
  @moduledoc """
  GenStage producer for the Import pipeline.

  Subscribes to `MediaCentarr.Topics.pipeline_matched()` for `{:file_matched}`
  events from the Discovery pipeline and Review approvals. Converts them to
  `%Payload{}` structs and dispatches to Broadway processors on demand.
  """
  use GenStage
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Pipeline.Payload

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_matched())
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
  def handle_info(
        {:file_matched,
         %{
           file_path: file_path,
           watch_dir: _watch_dir,
           tmdb_id: tmdb_id,
           tmdb_type: tmdb_type
         } = data},
        state
      ) do
    payload = build_payload(data)

    Log.info(
      :pipeline,
      "import queued #{Path.basename(file_path)} — " <>
        "tmdb:#{tmdb_id} (#{tmdb_type})" <>
        if(data[:pending_file_id], do: " [review]", else: "")
    )

    state = %{state | queue: :queue.in(payload, state.queue)}
    {messages, state} = dispatch(state)
    emit_queue_depth(state.queue)
    {:noreply, messages, state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  def ack(:ack_id, _successful, _failed), do: :ok

  @doc """
  Builds a `%Payload{}` from a file-matched event.

  Exposed as a public function for testing.
  """
  @spec build_payload(map()) :: Payload.t()
  def build_payload(
        %{
          file_path: file_path,
          watch_dir: watch_dir,
          tmdb_id: tmdb_id,
          tmdb_type: tmdb_type
        } = data
      ) do
    %Payload{
      file_path: file_path,
      watch_directory: watch_dir,
      tmdb_id: tmdb_id,
      tmdb_type: validated_tmdb_type(tmdb_type),
      pending_file_id: data[:pending_file_id]
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

  defp validated_tmdb_type(:movie), do: :movie
  defp validated_tmdb_type(:tv), do: :tv
  defp validated_tmdb_type("movie"), do: :movie
  defp validated_tmdb_type("tv"), do: :tv

  defp validated_tmdb_type(other) do
    raise ArgumentError, "invalid tmdb_type: #{inspect(other)}, expected :movie/:tv"
  end

  defp emit_queue_depth(queue) do
    :telemetry.execute(
      [:media_centarr, :pipeline, :queue_depth],
      %{depth: :queue.len(queue)},
      %{pipeline: :import}
    )
  end
end
