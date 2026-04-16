defmodule MediaCentarr.ImagePipeline.Stats do
  @moduledoc """
  Tracks image pipeline activity for Status-page visualization.

  Attaches to telemetry events emitted by `ImagePipeline` and its `Producer`,
  receives updates via `GenServer.cast`, and serves snapshots via
  `GenServer.call`. Each telemetry handler runs in the caller's process
  (a Broadway processor) and sends a cast to avoid blocking.

  ## State

  - `active_count` — currently executing processors
  - `window_completions` — `[{monotonic_ms, duration_native}]` for rolling throughput
  - `error_count` — lifetime errors
  - `last_error` — `{message, monotonic_ms} | nil`

  ## Lifetime counters

  - `total_downloaded` — successfully processed images
  - `total_failed` — lifetime failures (exceptions + error results)

  ## Recent errors

  A bounded ring buffer (`recent_errors`) stores the last 20
  image pipeline errors. Each entry is a map with `file_path`,
  `error_message`, `stage`, and `updated_at` — shaped to match what the
  Status errors table expects.

  ## Status derivation (computed at snapshot time)

  - `:erroring` — active and recent errors in window
  - `:saturated` — active_count >= 3 (of 4 processors)
  - `:active` — active_count > 0
  - `:idle` — active_count == 0
  """
  use GenServer

  alias MediaCentarr.StatsHelpers

  @window_ms 5_000
  @saturated_threshold 3
  @max_recent_errors 20

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a snapshot of current image pipeline statistics.
  """
  def get_snapshot(server \\ __MODULE__) do
    GenServer.call(server, :get_snapshot)
  end

  def download_start(server \\ __MODULE__, role, entity_id) do
    GenServer.cast(server, {:download_start, role, entity_id})
  end

  def download_stop(server \\ __MODULE__, duration, result, role, entity_id, error_reason \\ nil) do
    GenServer.cast(server, {:download_stop, duration, result, role, entity_id, error_reason})
  end

  def download_exception(server \\ __MODULE__, duration, reason, role, entity_id) do
    GenServer.cast(server, {:download_exception, duration, reason, role, entity_id})
  end

  def queue_depth(server \\ __MODULE__, depth) do
    GenServer.cast(server, {:queue_depth, depth})
  end

  @doc """
  Returns an empty snapshot for use before the GenServer starts
  (e.g., in disconnected LiveView mount).
  """
  def empty_snapshot do
    %{
      status: :idle,
      active_count: 0,
      throughput: 0.0,
      avg_duration_ms: nil,
      error_count: 0,
      last_error: nil,
      queue_depth: 0,
      total_downloaded: 0,
      total_failed: 0,
      recent_errors: []
    }
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    state = %{
      active_count: 0,
      window_completions: [],
      error_count: 0,
      last_error: nil,
      queue_depth: 0,
      total_downloaded: 0,
      total_failed: 0,
      recent_errors: []
    }

    attach_telemetry()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_snapshot, _from, state) do
    now = System.monotonic_time(:millisecond)

    # Prune completions and write back to state to prevent unbounded growth
    completions = StatsHelpers.prune_window(state.window_completions, now, @window_ms)
    throughput = StatsHelpers.calculate_throughput(completions, @window_ms)
    avg_duration = StatsHelpers.calculate_avg_duration(completions)

    status =
      StatsHelpers.derive_status(
        state.active_count,
        state.last_error,
        now,
        @window_ms,
        @saturated_threshold
      )

    snapshot = %{
      status: status,
      active_count: state.active_count,
      throughput: throughput,
      avg_duration_ms: avg_duration,
      error_count: state.error_count,
      last_error: state.last_error,
      queue_depth: state.queue_depth,
      total_downloaded: state.total_downloaded,
      total_failed: state.total_failed,
      recent_errors: state.recent_errors
    }

    {:reply, snapshot, %{state | window_completions: completions}}
  end

  @impl true
  def handle_cast({:download_start, _role, _entity_id}, state) do
    {:noreply, %{state | active_count: state.active_count + 1}}
  end

  def handle_cast({:download_stop, duration, result, role, entity_id, error_reason}, state) do
    now = System.monotonic_time(:millisecond)

    state = %{
      state
      | active_count: max(state.active_count - 1, 0),
        window_completions: [{now, duration} | state.window_completions]
    }

    state =
      case result do
        :ok ->
          %{state | total_downloaded: state.total_downloaded + 1}

        :error ->
          state
          |> Map.update!(:total_failed, &(&1 + 1))
          |> Map.update!(:error_count, &(&1 + 1))
          |> Map.put(:last_error, {StatsHelpers.format_error_reason(error_reason), now})
          |> record_error(role, entity_id, error_reason || "download failed")
      end

    {:noreply, state}
  end

  def handle_cast({:download_exception, duration, reason, role, entity_id}, state) do
    now = System.monotonic_time(:millisecond)

    state = %{
      state
      | active_count: max(state.active_count - 1, 0),
        window_completions: [{now, duration} | state.window_completions],
        error_count: state.error_count + 1,
        last_error: {StatsHelpers.format_error_reason(reason), now},
        total_failed: state.total_failed + 1
    }

    state = record_error(state, role, entity_id, reason)

    {:noreply, state}
  end

  def handle_cast({:queue_depth, depth}, state) do
    {:noreply, %{state | queue_depth: depth}}
  end

  # --- Private ---

  defp record_error(state, role, entity_id, reason) do
    entry = %{
      file_path: "#{entity_id}/#{role}",
      error_message: StatsHelpers.format_error_reason(reason),
      stage: :download_resize,
      updated_at: DateTime.utc_now()
    }

    errors = Enum.take([entry | state.recent_errors], @max_recent_errors)
    %{state | recent_errors: errors}
  end

  # --- Telemetry wiring ---

  defp attach_telemetry do
    :telemetry.detach("image-pipeline-stats")

    :telemetry.attach_many(
      "image-pipeline-stats",
      [
        [:media_centarr, :image_pipeline, :download, :start],
        [:media_centarr, :image_pipeline, :download, :stop],
        [:media_centarr, :image_pipeline, :download, :exception],
        [:media_centarr, :image_pipeline, :queue_depth]
      ],
      &__MODULE__.handle_telemetry/4,
      %{stats: self()}
    )
  end

  @doc false
  def handle_telemetry(
        [:media_centarr, :image_pipeline, :download, :start],
        _measurements,
        metadata,
        config
      ) do
    download_start(config.stats, metadata.role, metadata.entity_id)
  end

  def handle_telemetry(
        [:media_centarr, :image_pipeline, :download, :stop],
        measurements,
        metadata,
        config
      ) do
    download_stop(
      config.stats,
      measurements.duration,
      metadata.result,
      metadata.role,
      metadata.entity_id,
      metadata[:error_reason]
    )
  end

  def handle_telemetry(
        [:media_centarr, :image_pipeline, :download, :exception],
        measurements,
        metadata,
        config
      ) do
    download_exception(
      config.stats,
      measurements.duration,
      metadata.reason,
      metadata.role,
      metadata.entity_id
    )
  end

  def handle_telemetry(
        [:media_centarr, :image_pipeline, :queue_depth],
        measurements,
        _metadata,
        config
      ) do
    queue_depth(config.stats, measurements.depth)
  end
end
