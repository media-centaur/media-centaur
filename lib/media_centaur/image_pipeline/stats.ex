defmodule MediaCentaur.ImagePipeline.Stats do
  @moduledoc """
  Tracks image pipeline activity for dashboard visualization.

  Attaches to telemetry events emitted by `ImagePipeline` and its `Producer`,
  receives updates via `GenServer.cast`, and serves snapshots via
  `GenServer.call`. Each telemetry handler runs in the caller's process
  (a Broadway processor) and sends a cast to avoid blocking.

  ## State

  - `active_count` — currently executing processors
  - `window_completions` — `[{monotonic_ms, duration_native}]` for rolling throughput
  - `error_count` — errors in current window
  - `last_error` — `{message, monotonic_ms} | nil`

  ## Lifetime counters

  - `total_downloaded` — successfully processed images
  - `total_failed` — lifetime failures (exceptions + error results)

  ## Recent errors

  A bounded ring buffer (`recent_errors`) stores the last 20
  image pipeline errors. Each entry is a map with `file_path`,
  `error_message`, `stage`, and `updated_at` — shaped to match what the
  dashboard errors table expects.

  ## Status derivation (computed at snapshot time)

  - `:erroring` — active and recent errors in window
  - `:saturated` — active_count >= 3 (of 4 processors)
  - `:active` — active_count > 0
  - `:idle` — active_count == 0
  """
  use GenServer

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

    completions = prune_window(state.window_completions, now)
    throughput = calculate_throughput(completions)
    avg_duration = calculate_avg_duration(completions)
    status = derive_status(state.active_count, state.last_error, now)

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

    {:reply, snapshot, state}
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
          |> Map.put(:last_error, {format_error_reason(error_reason), now})
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
        last_error: {format_error_reason(reason), now},
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
      error_message: format_error_reason(reason),
      stage: :download_resize,
      updated_at: DateTime.utc_now()
    }

    errors = Enum.take([entry | state.recent_errors], @max_recent_errors)
    %{state | recent_errors: errors}
  end

  defp format_error_reason(reason) when is_binary(reason), do: reason
  defp format_error_reason(reason), do: inspect(reason)

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
    :telemetry.detach("image-pipeline-stats")

    :telemetry.attach_many(
      "image-pipeline-stats",
      [
        [:media_centaur, :image_pipeline, :download, :start],
        [:media_centaur, :image_pipeline, :download, :stop],
        [:media_centaur, :image_pipeline, :download, :exception],
        [:media_centaur, :image_pipeline, :queue_depth]
      ],
      &__MODULE__.handle_telemetry/4,
      %{stats: self()}
    )
  end

  @doc false
  def handle_telemetry(
        [:media_centaur, :image_pipeline, :download, :start],
        _measurements,
        metadata,
        config
      ) do
    GenServer.cast(config.stats, {:download_start, metadata.role, metadata.entity_id})
  end

  def handle_telemetry(
        [:media_centaur, :image_pipeline, :download, :stop],
        measurements,
        metadata,
        config
      ) do
    GenServer.cast(
      config.stats,
      {:download_stop, measurements.duration, metadata.result, metadata.role, metadata.entity_id,
       metadata[:error_reason]}
    )
  end

  def handle_telemetry(
        [:media_centaur, :image_pipeline, :download, :exception],
        measurements,
        metadata,
        config
      ) do
    GenServer.cast(
      config.stats,
      {:download_exception, measurements.duration, metadata.reason, metadata.role,
       metadata.entity_id}
    )
  end

  def handle_telemetry(
        [:media_centaur, :image_pipeline, :queue_depth],
        measurements,
        _metadata,
        config
      ) do
    GenServer.cast(config.stats, {:queue_depth, measurements.depth})
  end
end
