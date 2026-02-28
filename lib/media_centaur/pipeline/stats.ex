defmodule MediaCentaur.Pipeline.Stats do
  @moduledoc """
  Tracks pipeline stage activity for dashboard visualization.

  Attaches to telemetry events emitted by `Pipeline` and `Producer`,
  receives updates via `GenServer.cast`, and serves snapshots via
  `GenServer.call`. Each telemetry handler runs in the caller's process
  (a Broadway processor) and sends a cast to avoid blocking.

  ## Per-stage state

  - `active_count` — currently executing processors
  - `window_completions` — `[{monotonic_ms, duration_native}]` for rolling throughput
  - `error_count` — lifetime errors
  - `last_error` — `{message, monotonic_ms} | nil`

  ## Status derivation (computed at snapshot time)

  - `:erroring` — active and recent errors in window
  - `:saturated` — active_count >= 10 (of 15 processors)
  - `:active` — active_count > 0
  - `:idle` — active_count == 0
  """
  use GenServer

  @stages [:parse, :search, :fetch_metadata, :download_images, :ingest]
  @window_ms 5_000
  @saturated_threshold 10

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a snapshot of current pipeline statistics.

  Includes per-stage status, throughput, active counts, and lifetime counters.
  When called on the named process, also includes rate limiter status.
  """
  def get_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :get_snapshot)
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
      total_processed: 0,
      total_failed: 0,
      needs_review_count: 0,
      rate_limiter: nil
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
      queue_depth: 0,
      total_processed: 0,
      total_failed: 0,
      needs_review_count: 0
    }

    attach_telemetry()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_snapshot, _from, state) do
    now = System.monotonic_time(:millisecond)

    stages =
      Map.new(state.stages, fn {stage, data} ->
        completions = prune_window(data.window_completions, now)
        throughput = calculate_throughput(completions)
        avg_duration = calculate_avg_duration(completions)
        status = derive_status(data.active_count, data.last_error, now)

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

    rate_limiter =
      try do
        MediaCentaur.TMDB.RateLimiter.status()
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end

    snapshot = %{
      stages: stages,
      queue_depth: state.queue_depth,
      total_processed: state.total_processed,
      total_failed: state.total_failed,
      needs_review_count: state.needs_review_count,
      rate_limiter: rate_limiter
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_cast({:stage_start, stage, _file_path}, state) do
    state =
      update_stage(state, stage, fn data ->
        %{data | active_count: data.active_count + 1}
      end)

    {:noreply, state}
  end

  def handle_cast({:stage_stop, stage, duration, result}, state) do
    now = System.monotonic_time(:millisecond)
    handle_stage_stop(state, stage, duration, result, now)
  end

  def handle_cast({:stage_stop_at, stage, duration, result, timestamp}, state) do
    handle_stage_stop(state, stage, duration, result, timestamp)
  end

  def handle_cast({:stage_exception, stage, _duration, reason}, state) do
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

    {:noreply, state}
  end

  def handle_cast({:needs_review, _file_path}, state) do
    {:noreply, %{state | needs_review_count: state.needs_review_count + 1}}
  end

  def handle_cast({:queue_depth, depth}, state) do
    {:noreply, %{state | queue_depth: depth}}
  end

  # --- Private ---

  defp handle_stage_stop(state, stage, duration, result, timestamp) do
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
        {:ingest, :ok} -> %{state | total_processed: state.total_processed + 1}
        {_, :error} -> %{state | total_failed: state.total_failed + 1}
        _ -> state
      end

    {:noreply, state}
  end

  defp update_stage(state, stage, fun) do
    %{state | stages: Map.update!(state.stages, stage, fun)}
  end

  defp prune_window(completions, now) do
    cutoff = now - @window_ms
    Enum.filter(completions, fn {ts, _duration} -> ts >= cutoff end)
  end

  defp calculate_throughput([]), do: 0.0

  defp calculate_throughput(completions) do
    count = length(completions)
    Float.round(count / (@window_ms / 1_000), 1)
  end

  defp calculate_avg_duration([]), do: nil

  defp calculate_avg_duration(completions) do
    total =
      completions
      |> Enum.map(fn {_ts, duration} -> duration end)
      |> Enum.sum()

    avg_native = total / length(completions)
    Float.round(System.convert_time_unit(round(avg_native), :native, :millisecond) / 1, 1)
  end

  defp derive_status(active_count, last_error, now) do
    has_recent_error =
      case last_error do
        {_msg, error_time} -> now - error_time < @window_ms
        nil -> false
      end

    cond do
      active_count > 0 and has_recent_error -> :erroring
      active_count >= @saturated_threshold -> :saturated
      active_count > 0 -> :active
      true -> :idle
    end
  end

  # --- Telemetry wiring ---

  defp attach_telemetry do
    :telemetry.attach_many(
      "pipeline-stats",
      [
        [:media_centaur, :pipeline, :stage, :start],
        [:media_centaur, :pipeline, :stage, :stop],
        [:media_centaur, :pipeline, :stage, :exception],
        [:media_centaur, :pipeline, :needs_review],
        [:media_centaur, :pipeline, :queue_depth]
      ],
      &handle_telemetry/4,
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
    GenServer.cast(config.stats, {:stage_start, metadata.stage, metadata.file_path})
  end

  def handle_telemetry([:media_centaur, :pipeline, :stage, :stop], measurements, metadata, config) do
    GenServer.cast(
      config.stats,
      {:stage_stop, metadata.stage, measurements.duration, metadata.result}
    )
  end

  def handle_telemetry(
        [:media_centaur, :pipeline, :stage, :exception],
        measurements,
        metadata,
        config
      ) do
    GenServer.cast(
      config.stats,
      {:stage_exception, metadata.stage, measurements.duration, metadata.reason}
    )
  end

  def handle_telemetry(
        [:media_centaur, :pipeline, :needs_review],
        _measurements,
        metadata,
        config
      ) do
    GenServer.cast(config.stats, {:needs_review, metadata.file_path})
  end

  def handle_telemetry([:media_centaur, :pipeline, :queue_depth], measurements, _metadata, config) do
    GenServer.cast(config.stats, {:queue_depth, measurements.depth})
  end
end
