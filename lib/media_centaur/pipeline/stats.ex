defmodule MediaCentaur.Pipeline.Stats do
  @moduledoc """
  Tracks pipeline stage activity for dashboard visualization.

  Attaches to telemetry events emitted by Discovery, Import, and their
  producers, receives updates via `GenServer.cast`, and serves snapshots
  via `GenServer.call`. Each telemetry handler runs in the caller's process
  (a Broadway processor) and sends a cast to avoid blocking.

  Tracks stages across both pipelines (Discovery owns `:parse` and `:search`,
  Import owns `:fetch_metadata` and `:ingest`). Queue depths are tracked
  per-pipeline.

  ## Per-stage state

  - `active_count` — currently executing processors
  - `window_completions` — `[{monotonic_ms, duration_native}]` for rolling throughput
  - `error_count` — lifetime errors
  - `last_error` — `{message, monotonic_ms} | nil`

  ## Recent errors

  A bounded ring buffer (`recent_errors`) stores the last 50
  pipeline errors across all stages. Each entry is a map with `file_path`,
  `error_message`, `stage`, and `updated_at` — shaped to match what the
  dashboard errors table expects.

  ## Status derivation (computed at snapshot time)

  - `:erroring` — active and recent errors in window
  - `:saturated` — active_count >= saturated threshold
  - `:active` — active_count > 0
  - `:idle` — active_count == 0
  """
  use GenServer

  alias MediaCentaur.StatsHelpers

  @stages [:parse, :search, :fetch_metadata, :ingest]
  @window_ms 5_000
  @saturated_threshold 10
  @max_recent_errors 50

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a snapshot of current pipeline statistics.

  Includes per-stage status, throughput, active counts, lifetime counters,
  and recent errors. `queue_depth` is the sum of both pipeline queue depths.
  """
  def get_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :get_snapshot)
  end

  def stage_start(server \\ __MODULE__, stage, file_path) do
    GenServer.cast(server, {:stage_start, stage, file_path})
  end

  def stage_stop(server \\ __MODULE__, stage, duration, result, file_path, error_reason \\ nil) do
    GenServer.cast(server, {:stage_stop, stage, duration, result, file_path, error_reason})
  end

  def stage_stop_at(server, stage, duration, result, timestamp, file_path, error_reason \\ nil) do
    GenServer.cast(
      server,
      {:stage_stop_at, stage, duration, result, timestamp, file_path, error_reason}
    )
  end

  def stage_exception(server \\ __MODULE__, stage, duration, reason, file_path) do
    GenServer.cast(server, {:stage_exception, stage, duration, reason, file_path})
  end

  def needs_review(server \\ __MODULE__, file_path) do
    GenServer.cast(server, {:needs_review, file_path})
  end

  def queue_depth(server \\ __MODULE__, pipeline, depth) do
    GenServer.cast(server, {:queue_depth, pipeline, depth})
  end

  @doc """
  Returns an empty snapshot for use before the GenServer starts
  (e.g., in disconnected LiveView mount).
  """
  def empty_snapshot do
    stages =
      Map.new(@stages, fn stage ->
        {stage,
         %{
           active_count: 0,
           status: :idle,
           throughput: 0.0,
           error_count: 0,
           last_error: nil,
           avg_duration_ms: nil
         }}
      end)

    %{
      stages: stages,
      queue_depth: 0,
      discovery_queue_depth: 0,
      import_queue_depth: 0,
      total_processed: 0,
      total_failed: 0,
      needs_review_count: 0,
      recent_errors: []
    }
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    stage_state =
      Map.new(@stages, fn stage ->
        {stage,
         %{
           active_count: 0,
           window_completions: [],
           error_count: 0,
           last_error: nil
         }}
      end)

    state = %{
      stages: stage_state,
      discovery_queue_depth: 0,
      import_queue_depth: 0,
      total_processed: 0,
      total_failed: 0,
      needs_review_count: 0,
      recent_errors: []
    }

    attach_telemetry()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_snapshot, _from, state) do
    now = System.monotonic_time(:millisecond)

    # Prune completions and write back to state to prevent unbounded growth
    pruned_stages =
      Map.new(state.stages, fn {stage, data} ->
        {stage,
         %{
           data
           | window_completions:
               StatsHelpers.prune_window(data.window_completions, now, @window_ms)
         }}
      end)

    stages =
      Map.new(pruned_stages, fn {stage, data} ->
        throughput = StatsHelpers.calculate_throughput(data.window_completions, @window_ms)
        avg_duration = StatsHelpers.calculate_avg_duration(data.window_completions)

        status =
          StatsHelpers.derive_status(
            data.active_count,
            data.last_error,
            now,
            @window_ms,
            @saturated_threshold
          )

        {stage,
         %{
           active_count: data.active_count,
           status: status,
           throughput: throughput,
           error_count: data.error_count,
           last_error: data.last_error,
           avg_duration_ms: avg_duration
         }}
      end)

    snapshot = %{
      stages: stages,
      queue_depth: state.discovery_queue_depth + state.import_queue_depth,
      discovery_queue_depth: state.discovery_queue_depth,
      import_queue_depth: state.import_queue_depth,
      total_processed: state.total_processed,
      total_failed: state.total_failed,
      needs_review_count: state.needs_review_count,
      recent_errors: state.recent_errors
    }

    {:reply, snapshot, %{state | stages: pruned_stages}}
  end

  @impl true
  def handle_cast({:stage_start, stage, _file_path}, state) do
    state =
      update_stage(state, stage, fn data ->
        %{data | active_count: data.active_count + 1}
      end)

    {:noreply, state}
  end

  def handle_cast({:stage_stop, stage, duration, result, file_path, error_reason}, state) do
    now = System.monotonic_time(:millisecond)
    handle_stage_stop(state, stage, duration, result, now, file_path, error_reason)
  end

  def handle_cast(
        {:stage_stop_at, stage, duration, result, timestamp, file_path, error_reason},
        state
      ) do
    handle_stage_stop(state, stage, duration, result, timestamp, file_path, error_reason)
  end

  def handle_cast({:stage_exception, stage, _duration, reason, file_path}, state) do
    now = System.monotonic_time(:millisecond)

    state =
      state
      |> update_stage(stage, fn data ->
        %{
          data
          | active_count: max(data.active_count - 1, 0),
            error_count: data.error_count + 1,
            last_error: {reason, now}
        }
      end)
      |> Map.update!(:total_failed, &(&1 + 1))
      |> record_error(stage, file_path, reason)

    {:noreply, state}
  end

  def handle_cast({:needs_review, _file_path}, state) do
    {:noreply, %{state | needs_review_count: state.needs_review_count + 1}}
  end

  def handle_cast({:queue_depth, :discovery, depth}, state) do
    {:noreply, %{state | discovery_queue_depth: depth}}
  end

  def handle_cast({:queue_depth, :import, depth}, state) do
    {:noreply, %{state | import_queue_depth: depth}}
  end

  # --- Private ---

  defp handle_stage_stop(state, stage, duration, result, timestamp, file_path, error_reason) do
    state =
      update_stage(state, stage, fn data ->
        %{
          data
          | active_count: max(data.active_count - 1, 0),
            window_completions: [{timestamp, duration} | data.window_completions]
        }
      end)

    state =
      case {stage, result} do
        {:ingest, :ok} ->
          %{state | total_processed: state.total_processed + 1}

        {_, :error} ->
          state
          |> Map.update!(:total_failed, &(&1 + 1))
          |> record_error(stage, file_path, error_reason || "stage returned error")

        _ ->
          state
      end

    {:noreply, state}
  end

  defp record_error(state, stage, file_path, reason) do
    entry = %{
      file_path: file_path,
      error_message: StatsHelpers.format_error_reason(reason),
      stage: stage,
      updated_at: DateTime.utc_now()
    }

    errors = Enum.take([entry | state.recent_errors], @max_recent_errors)
    %{state | recent_errors: errors}
  end

  defp update_stage(state, stage, fun) do
    %{state | stages: Map.update!(state.stages, stage, fun)}
  end

  # --- Telemetry wiring ---

  defp attach_telemetry do
    :telemetry.detach("pipeline-stats")

    :telemetry.attach_many(
      "pipeline-stats",
      [
        [:media_centaur, :pipeline, :stage, :start],
        [:media_centaur, :pipeline, :stage, :stop],
        [:media_centaur, :pipeline, :stage, :exception],
        [:media_centaur, :pipeline, :needs_review],
        [:media_centaur, :pipeline, :queue_depth]
      ],
      &__MODULE__.handle_telemetry/4,
      %{stats: self()}
    )
  end

  @doc false
  def handle_telemetry(
        [:media_centaur, :pipeline, :stage, :start],
        _measurements,
        metadata,
        config
      ) do
    stage_start(config.stats, metadata.stage, metadata.file_path)
  end

  def handle_telemetry([:media_centaur, :pipeline, :stage, :stop], measurements, metadata, config) do
    stage_stop(
      config.stats,
      metadata.stage,
      measurements.duration,
      metadata.result,
      metadata.file_path,
      metadata[:error_reason]
    )
  end

  def handle_telemetry(
        [:media_centaur, :pipeline, :stage, :exception],
        measurements,
        metadata,
        config
      ) do
    stage_exception(
      config.stats,
      metadata.stage,
      measurements.duration,
      metadata.reason,
      metadata.file_path
    )
  end

  def handle_telemetry(
        [:media_centaur, :pipeline, :needs_review],
        _measurements,
        metadata,
        config
      ) do
    needs_review(config.stats, metadata.file_path)
  end

  def handle_telemetry([:media_centaur, :pipeline, :queue_depth], measurements, metadata, config) do
    queue_depth(config.stats, metadata.pipeline, measurements.depth)
  end
end
