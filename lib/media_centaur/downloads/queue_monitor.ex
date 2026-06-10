defmodule MediaCentaur.Downloads.QueueMonitor do
  @moduledoc """
  Polls the configured download client and broadcasts a versioned
  `%QueueState{}` snapshot. Replaces per-LiveView polling so multiple
  consumers (Downloads page + Library upcoming zone) share a single
  connection.

  ## Cache + broadcast

  - Each successful poll caches the `%QueueState{}` in `:persistent_term`
    for cheap synchronous reads via
    `MediaCentaur.Acquisition.queue_state/0`.
  - Each successful poll also broadcasts `{:queue_state, state}` on
    `Topics.acquisition_queue()` so subscribers can refresh live.
  - On `register_subscriber/1`, the current `%QueueState{}` is sent
    directly to the registering pid — no waiting for the next poll
    tick. Eliminates the mount-race that made first paint feel stale.

  ## Subscriber-aware cadence

  The poll interval scales with whether anyone is watching:

  - **10 s** when at least one LiveView is subscribed AND the download
    client is ready — fresh enough for an open queue view without
    hammering the client (and without flooding the logs).
  - **30 s** when ready but nobody is watching — just keeps the cache
    from going stale.
  - **30 s** when the client is offline — back off so the eventual
    reconfigure picks up within a reasonable window.

  Subscribers register implicitly via `Acquisition.subscribe_queue/0`,
  which calls `register_subscriber/1`. We `Process.monitor/1` each one
  and drop them on `:DOWN`.

  ## Failure handling

  Errors from the download client are logged and the previous
  `%QueueState{}` is kept in cache, but `:last_error` is updated and
  rebroadcast so subscribers can render a staleness indicator.

  ## Health classification

  After each successful poll the items are enriched with a `:health`
  field per item via `MediaCentaur.Downloads.HealthHistory`. The
  throughput history needed to classify items lives in this
  GenServer's state; only this module updates it.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.Downloads.DownloadClient.SyncResult
  alias MediaCentaur.Downloads.HealthHistory
  alias MediaCentaur.Downloads.QueueState
  alias MediaCentaur.Topics

  @cache_key {__MODULE__, :state}
  @poll_watched_ms 10_000
  @poll_idle_ms 30_000
  @poll_offline_ms 30_000

  # Steady-state sync ticks (no real queue movement) repeat every
  # @poll_watched_ms while a LiveView is open. Logging each one at :info
  # floods the in-memory Console ring buffer and pushes every other
  # subsystem's lines out of it — the opposite of an observability aid.
  # We log real movement immediately and otherwise emit at most one
  # :info heartbeat per this interval so "is it still polling?" stays
  # answerable from the default buffer.
  @sync_log_heartbeat_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the latest cached `%QueueState{}`. Synchronous, no GenServer
  call — reads `:persistent_term`. Returns an empty `%QueueState{}`
  before the first poll.
  """
  @spec state() :: QueueState.t()
  def state do
    case :persistent_term.get(@cache_key, nil) do
      %QueueState{} = state -> state
      _ -> %QueueState{}
    end
  end

  @doc """
  Backwards-compatible accessor for the items list. New code should
  prefer `state/0` and read `state.items` so it can reason about
  freshness via `QueueStatus.derive/2`.
  """
  @spec snapshot() :: [Acquisition.QueueItem.t()]
  def snapshot, do: state().items

  @doc """
  Triggers an immediate poll without disturbing the scheduled cadence.
  Used when an external event makes us suspect the cached snapshot is
  stale — e.g. a user just configured the download client and we'd
  otherwise wait up to 30 s for the next idle-cadence tick.
  """
  @spec poll_now() :: :ok
  def poll_now, do: GenServer.cast(__MODULE__, :poll_now)

  @doc """
  Registers `pid` as an active subscriber and immediately sends it
  the current `%QueueState{}`. The next poll uses the watched cadence.
  Idempotent — re-registering re-sends the current state but doesn't
  re-monitor. Pid is dropped automatically when the process exits.

  Called from `Acquisition.subscribe_queue/0`; LiveViews should not
  call this directly.
  """
  @spec register_subscriber(pid()) :: :ok
  def register_subscriber(pid) when is_pid(pid), do: GenServer.cast(__MODULE__, {:register, pid})

  @doc """
  Returns the poll cadence in milliseconds for the given subscriber
  count, download-client-ready flag, and last error reason. Pure —
  extracted for unit testing the contract without spinning up a
  GenServer.

  `:auth_failed` deliberately overrides the watched/idle cadence:
  `Capabilities.last_test_ok?` lags reality (a successful
  `test_connection` at config time stays "ok" until the user re-tests),
  so without this row, a credential rotation on the qBittorrent side
  silently log-spams at the watched cadence against an auth-broken
  client until the user reconfigures.
  """
  @spec cadence_ms(non_neg_integer(), boolean(), QueueState.error_reason()) :: pos_integer()
  def cadence_ms(_subscribers, _ready?, :auth_failed), do: @poll_offline_ms
  def cadence_ms(_subscribers, false, _error), do: @poll_offline_ms
  def cadence_ms(0, true, _error), do: @poll_idle_ms
  def cadence_ms(_subscribers, true, _error), do: @poll_watched_ms

  @doc """
  Log level for a sync tick. Real movement always logs at `:info`.
  Steady-state ticks (no movement — the common case, repeating every
  #{@poll_watched_ms} ms while watched) are `:skip`ped so they don't
  flood the Console ring buffer, except for one `:info` heartbeat once
  at least `heartbeat_ms` has elapsed since the last logged line.
  """
  @spec sync_log_level(boolean(), non_neg_integer(), pos_integer()) :: :info | :skip
  def sync_log_level(movement?, ms_since_last_log, heartbeat_ms \\ @sync_log_heartbeat_ms)
  def sync_log_level(true, _ms_since, _heartbeat), do: :info
  def sync_log_level(false, ms_since, heartbeat) when ms_since >= heartbeat, do: :info
  def sync_log_level(false, _ms_since, _heartbeat), do: :skip

  @impl GenServer
  def init(_opts) do
    Process.send_after(self(), :poll, 0)

    {:ok,
     %{
       queue: %QueueState{},
       subscribers: %{},
       history: %{},
       last_sync_log_ms: nil,
       # The configured driver module + its opaque sync bookmark
       # (`DownloadClient.driver_state`). The bookmark is reset whenever
       # the driver module changes between polls.
       driver: nil,
       driver_state: nil
     }}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    ready? = Capabilities.download_client_ready?()
    state = if ready?, do: poll_and_broadcast(state), else: state

    delay = cadence_ms(map_size(state.subscribers), ready?, state.queue.last_error)
    Process.send_after(self(), :poll, delay)

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast(:poll_now, state) do
    state = if Capabilities.download_client_ready?(), do: poll_and_broadcast(state), else: state
    {:noreply, state}
  end

  def handle_cast({:register, pid}, state) do
    send(pid, {:queue_state, state.queue})

    if Map.has_key?(state.subscribers, pid) do
      {:noreply, state}
    else
      ref = Process.monitor(pid)
      {:noreply, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  defp poll_and_broadcast(state) do
    case Dispatcher.driver() do
      {:ok, driver} -> run_sync(state, driver)
      {:error, _not_configured_or_unknown} -> mark_not_configured(state)
    end
  end

  defp run_sync(state, driver) do
    now = DateTime.utc_now()
    # A driver swap (user reconfigured the client type) invalidates the
    # old driver's opaque bookmark — start its conversation fresh.
    driver_state = if driver == state.driver, do: state.driver_state

    case driver.sync(driver_state) do
      {:ok, %SyncResult{} = result} ->
        last_sync_log_ms = log_sync_tick(result, state.last_sync_log_ms)
        active = Enum.reject(result.items, &(&1.state == :completed))

        {history, enriched} =
          HealthHistory.update(state.history, active, System.monotonic_time(:microsecond))

        queue = %QueueState{
          items: enriched,
          last_polled_at: now,
          last_successful_poll_at: now,
          last_error: nil
        }

        store_and_broadcast(queue)

        %{
          state
          | queue: queue,
            history: history,
            last_sync_log_ms: last_sync_log_ms,
            driver: driver,
            driver_state: result.driver_state
        }

      {:error, :not_configured, _driver_state} ->
        mark_not_configured(state)

      {:error, reason, next_driver_state} ->
        # The connectivity condition is owned by Downloads.IncidentContext.assess/0
        # (it reads the very last_error set just below) — console-only, no
        # duplicate :log incident (ADR-054). The driver hands back the
        # bookmark to carry forward (it resets its own conversation so the
        # next successful poll is a full update).
        Log.warning(:library, "queue monitor poll failed: #{inspect(reason)}", mc_incident: :skip)

        queue = %{state.queue | last_polled_at: now, last_error: classify_error(reason)}

        store_and_broadcast(queue)
        %{state | queue: queue, driver: driver, driver_state: next_driver_state}
    end
  end

  defp mark_not_configured(state) do
    queue = %QueueState{
      items: [],
      last_polled_at: DateTime.utc_now(),
      last_successful_poll_at: state.queue.last_successful_poll_at,
      last_error: :not_configured
    }

    store_and_broadcast(queue)
    %{state | queue: queue, history: %{}, driver: nil, driver_state: nil}
  end

  defp store_and_broadcast(%QueueState{} = queue) do
    :persistent_term.put(@cache_key, queue)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.acquisition_queue(),
      {:queue_state, queue}
    )
  end

  defp classify_error({:auth_failed, _}), do: :auth_failed
  defp classify_error(:auth_failed), do: :auth_failed
  defp classify_error(_), do: :unreachable

  # Emits the grep-able "is the subsystem actually polling?" signal —
  # but only for ticks worth seeing. Real movement always logs at :info
  # immediately; steady-state echoes are skipped except for a periodic
  # heartbeat so the Console ring buffer isn't flooded (see
  # @sync_log_heartbeat_ms). Movement detection and the line body come
  # from the driver (it knows its own delta format); the cadence policy
  # lives here. Returns the monotonic ms of the last logged line so the
  # caller can thread the heartbeat clock.
  defp log_sync_tick(%SyncResult{} = result, last_log_ms) do
    now_ms = System.monotonic_time(:millisecond)
    ms_since = if last_log_ms, do: now_ms - last_log_ms, else: @sync_log_heartbeat_ms

    case sync_log_level(result.movement?, ms_since) do
      :info ->
        Log.info(:acquisition, result.summary || "queue sync")
        now_ms

      :skip ->
        last_log_ms
    end
  end
end
