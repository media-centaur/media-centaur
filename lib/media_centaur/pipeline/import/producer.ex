defmodule MediaCentaur.Pipeline.Import.Producer do
  @moduledoc """
  GenStage producer for the Import pipeline.

  Subscribes to `MediaCentaur.Topics.pipeline_matched()` for `{:file_matched}`
  events from the Discovery pipeline and Review approvals. Converts them to
  `%Payload{}` structs and dispatches to Broadway processors on demand.
  """
  use GenStage
  @behaviour Broadway.Acknowledger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Pipeline.ProducerQueue

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(_opts) do
    MediaCentaur.Topics.subscribe(MediaCentaur.Topics.pipeline_matched())
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
         %{file_path: file_path, media_dir: _media_dir, tmdb_id: tmdb_id, tmdb_type: tmdb_type} = data},
        state
      ) do
    payload = build_payload(data)

    Log.info(:pipeline, "import queued #{Path.basename(file_path)} — tmdb:#{tmdb_id} (#{tmdb_type})")

    state = %{state | queue: :queue.in(payload, state.queue)}
    {messages, state} = dispatch(state)
    emit_queue_depth(state.queue)
    {:noreply, messages, state}
  end

  def handle_info(_msg, state) do
    {:noreply, [], state}
  end

  @impl Broadway.Acknowledger
  def ack(:ack_id, _successful, _failed), do: :ok

  @doc """
  Builds a `%Payload{}` from a file-matched event.

  The event is the match's identity: the TMDB id and type. The file's
  position is what its name claims, which Import parses itself; a
  position the name does not settle is decided in episode mapping.

  Exposed as a public function for testing.
  """
  @spec build_payload(map()) :: Payload.t()
  def build_payload(%{
        file_path: file_path,
        media_dir: media_dir,
        tmdb_id: tmdb_id,
        tmdb_type: tmdb_type
      }) do
    %Payload{
      file_path: file_path,
      media_directory: media_dir,
      tmdb_id: tmdb_id,
      tmdb_type: validated_tmdb_type(tmdb_type)
    }
  end

  defp dispatch(%{demand: 0} = state), do: {[], state}

  defp dispatch(state) do
    {payloads, queue, remaining_demand} = ProducerQueue.dequeue(state.queue, state.demand)
    messages = ProducerQueue.to_messages(payloads, __MODULE__)
    {messages, %{state | queue: queue, demand: remaining_demand}}
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
      [:media_centaur, :pipeline, :queue_depth],
      %{depth: :queue.len(queue)},
      %{pipeline: :import}
    )
  end
end
