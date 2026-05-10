defmodule MediaCentarr.Downloads.QueueMonitor do
  @moduledoc """
  Polls the configured download client and broadcasts a versioned
  `%QueueState{}` snapshot. Replaces per-LiveView polling so multiple
  consumers (Downloads page + Library upcoming zone) share a single
  connection.

  ## Cache + broadcast

  - Each successful poll caches the `%QueueState{}` in `:persistent_term`
    for cheap synchronous reads via
    `MediaCentarr.Acquisition.queue_state/0`.
  - Each successful poll also broadcasts `{:queue_state, state}` on
    `Topics.acquisition_queue()` so subscribers can refresh live.
  - On `register_subscriber/1`, the current `%QueueState{}` is sent
    directly to the registering pid — no waiting for the next poll
    tick. Eliminates the mount-race that made first paint feel stale.

  ## Subscriber-aware cadence

  The poll interval scales with whether anyone is watching:

  - **1 s** when at least one LiveView is subscribed AND the download
    client is ready — the row needs to feel real-time.
  - **5 s** when ready but nobody is watching — keeps the cache warm
    without burning request budget on the client.
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
  field per item via `MediaCentarr.Downloads.HealthHistory`. The
  throughput history needed to classify items lives in this
  GenServer's state; only this module updates it.
  """
  use GenServer

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Downloads.DownloadClient.QBittorrent
  alias MediaCentarr.Downloads.DownloadClient.QBittorrent.Sync
  alias MediaCentarr.Downloads.HealthHistory
  alias MediaCentarr.Downloads.QueueState
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Topics

  @cache_key {__MODULE__, :state}
  @poll_watched_ms 1_500
  @poll_idle_ms 5_000
  @poll_offline_ms 30_000

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
  silently log-spams at 1.5 s against an auth-broken client until the
  user reconfigures.
  """
  @spec cadence_ms(non_neg_integer(), boolean(), QueueState.error_reason()) :: pos_integer()
  def cadence_ms(_subscribers, _ready?, :auth_failed), do: @poll_offline_ms
  def cadence_ms(_subscribers, false, _error), do: @poll_offline_ms
  def cadence_ms(0, true, _error), do: @poll_idle_ms
  def cadence_ms(_subscribers, true, _error), do: @poll_watched_ms

  @impl GenServer
  def init(_opts) do
    Process.send_after(self(), :poll, 0)
    {:ok, %{queue: %QueueState{}, subscribers: %{}, history: %{}}}
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
    now = DateTime.utc_now()

    case QBittorrent.sync_maindata(state.queue.rid) do
      {:ok, response} ->
        torrents = Sync.apply_maindata(state.queue.torrents, response)
        rid = Map.get(response, "rid", state.queue.rid)
        server_state = Map.merge(state.queue.server_state, Map.get(response, "server_state", %{}))

        log_sync_tick(response, state.queue.torrents, torrents)

        all_items = Sync.to_queue_items(torrents)
        active = Enum.reject(all_items, &(&1.state == :completed))

        {history, enriched} =
          HealthHistory.update(state.history, active, System.monotonic_time(:microsecond))

        queue = %QueueState{
          items: enriched,
          torrents: torrents,
          rid: rid,
          server_state: server_state,
          last_polled_at: now,
          last_successful_poll_at: now,
          last_error: nil
        }

        store_and_broadcast(queue)
        %{state | queue: queue, history: history}

      {:error, :not_configured} ->
        queue = %QueueState{
          items: [],
          torrents: %{},
          rid: 0,
          server_state: %{},
          last_polled_at: now,
          last_successful_poll_at: state.queue.last_successful_poll_at,
          last_error: :not_configured
        }

        store_and_broadcast(queue)
        %{state | queue: queue, history: %{}}

      {:error, reason} ->
        Log.warning(:library, "queue monitor poll failed: #{inspect(reason)}")

        queue = %{
          state.queue
          | last_polled_at: now,
            last_error: classify_error(reason),
            # Force a full update on the next successful poll — the
            # rid we have may be stale or the server may have lost it.
            rid: 0
        }

        store_and_broadcast(queue)
        %{state | queue: queue}
    end
  end

  defp store_and_broadcast(%QueueState{} = queue) do
    :persistent_term.put(@cache_key, queue)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.acquisition_queue(),
      {:queue_state, queue}
    )
  end

  defp classify_error({:auth_failed, _}), do: :auth_failed
  defp classify_error(:auth_failed), do: :auth_failed
  defp classify_error(_), do: :unreachable

  # One log line per successful sync — gives a grep-able "is the
  # subsystem actually polling?" signal for production troubleshooting.
  # `full_update` resets the count expectations; partial deltas show
  # how much of the queue moved this tick.
  defp log_sync_tick(response, before_torrents, after_torrents) do
    full? = Map.get(response, "full_update", false)
    rid = Map.get(response, "rid", 0)
    changed = response |> Map.get("torrents", %{}) |> map_size()
    removed = response |> Map.get("torrents_removed", []) |> length()
    added = max(0, map_size(after_torrents) - map_size(before_torrents) + removed)

    Log.info(
      :acquisition,
      "queue sync — rid=#{rid} full=#{full?} torrents=#{map_size(after_torrents)} added=#{added} changed=#{changed} removed=#{removed}"
    )
  end
end
