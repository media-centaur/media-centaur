defmodule MediaCentaur.Downloads.QueueMonitor do
  @moduledoc """
  Polls the configured download-client **set** (torrent + usenet slots,
  see `Dispatcher.drivers/0`) and broadcasts one merged, versioned
  `%QueueState{}` snapshot. Replaces per-LiveView polling so multiple
  consumers (Downloads page + Library upcoming zone) share a single
  connection per client.

  ## Multi-client merge

  Each tick polls every slot that is configured **and** connection-
  tested (`Capabilities.client_ready?/1`), each with its own opaque
  driver bookmark. The merged snapshot keeps the slots honest and
  independent:

  - Items concatenate torrent-slot first; every item is protocol-tagged
    by its driver.
  - `:completed` items are **kept** in the snapshot (usenet completion
    is only visible as a SABnzbd history entry, whose `storage` path is
    the `content_path` pursuit matching pins); they are excluded from
    health classification.
  - A failing client keeps its last-known items (staleness is expressed
    through its grade, not by items vanishing mid-outage) while the
    healthy client's items stay fresh.
  - `QueueState.connectivity` is the worst grade across slots;
    `QueueState.client_connectivity` carries the per-slot grades.

  The poll cadence is shared: an `:auth_failed` grade on either slot
  backs the whole cycle off to the 30 s backoff — slightly staler data
  for the healthy client in exchange for not hammering the broken one.

  ## Cache + broadcast

  - Each successful poll caches the `%QueueState{}` in `:persistent_term`
    for cheap synchronous reads via
    `MediaCentaur.Acquisition.queue_state/0`.
  - Each successful poll also broadcasts `{:queue_state, state}` on
    `Topics.acquisition_queue()` so subscribers can refresh live.
  - On `register_subscriber/1`, the current `%QueueState{}` is sent
    directly to the registering pid — no waiting for the next poll
    tick. Eliminates the mount-race that made first paint feel stale.
  - Registering the **first** subscriber also triggers an immediate
    poll and reschedules the cycle at the watched cadence — the cached
    snapshot may be up to an idle cadence old, and a freshly opened
    page shouldn't wait out a timer that was scheduled while nobody
    was watching.

  ## Subscriber-aware cadence

  The poll interval scales with whether anyone is watching:

  - **10 s** when at least one LiveView is subscribed AND the download
    client is ready — fresh enough for an open queue view without
    hammering the client (and without flooding the logs).
  - **30 s** when ready but nobody is watching — just keeps the cache
    from going stale.
  - **30 s** on auth failure or when no client is configured — back off
    so the eventual reconfigure picks up within a reasonable window.

  Subscribers register implicitly via `Acquisition.subscribe_queue/0`,
  which calls `register_subscriber/1`. We `Process.monitor/1` each one
  and drop them on `:DOWN`.

  Poll ticks are generation-tagged: every (re)schedule bumps a counter
  and stale tick messages are ignored, so an out-of-band reschedule
  (first subscriber) can never leave two timer chains running.

  ## Failure handling

  The monitor owns connectivity grading (`Downloads.Connectivity`):
  each poll outcome folds into the `connectivity` carried on the
  broadcast `%QueueState{}`. Failed polls keep the previous items in
  cache, log to the console, and rebroadcast with the new grade so
  subscribers render an honest staleness/outage indicator. Consumers
  never re-derive health from snapshot age.

  A stalled-but-alive monitor (no broadcasts at all) is deliberately
  not self-reported: driver requests carry HTTP timeouts and the
  process is supervised, so stall recovery is the supervisor's job,
  not a consumer-side age watchdog's.

  ## Health classification

  After each successful poll the items are enriched with a `:health`
  field per item via `MediaCentaur.Downloads.HealthHistory`. The
  throughput history needed to classify items lives in this
  GenServer's state; only this module updates it.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.Connectivity
  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.Downloads.DownloadClient.SyncResult
  alias MediaCentaur.Downloads.HealthHistory
  alias MediaCentaur.Downloads.QueueState
  alias MediaCentaur.Topics

  @cache_key {__MODULE__, :state}
  @poll_watched_ms 10_000
  @poll_idle_ms 30_000
  @poll_backoff_ms 30_000

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
  connectivity alongside the data.
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
  the current `%QueueState{}`. The first subscriber additionally
  triggers an immediate poll and reschedules at the watched cadence.
  Idempotent — re-registering re-sends the current state but doesn't
  re-monitor or re-poll. Pid is dropped automatically when the process
  exits.

  Called from `Acquisition.subscribe_queue/0`; LiveViews should not
  call this directly.
  """
  @spec register_subscriber(pid()) :: :ok
  def register_subscriber(pid) when is_pid(pid), do: GenServer.cast(__MODULE__, {:register, pid})

  @doc """
  Returns the poll cadence in milliseconds for the given subscriber
  count, download-client-ready flag, and current connectivity grade.
  Pure — extracted for unit testing the contract without spinning up a
  GenServer.

  `:auth_failed` deliberately overrides the watched/idle cadence:
  `Capabilities.last_test_ok?` lags reality (a successful
  `test_connection` at config time stays "ok" until the user re-tests),
  so without this row, a credential rotation on the qBittorrent side
  silently log-spams at the watched cadence against an auth-broken
  client until the user reconfigures. An `{:offline, _}` client keeps
  the watched cadence on purpose — recovery should be noticed promptly
  while someone is looking at the page.
  """
  @spec cadence_ms(non_neg_integer(), boolean(), Connectivity.t()) :: pos_integer()
  def cadence_ms(_subscribers, _ready?, :auth_failed), do: @poll_backoff_ms
  def cadence_ms(_subscribers, false, _connectivity), do: @poll_backoff_ms
  def cadence_ms(0, true, _connectivity), do: @poll_idle_ms
  def cadence_ms(_subscribers, true, _connectivity), do: @poll_watched_ms

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
    state = %{
      queue: %QueueState{},
      subscribers: %{},
      history: %{},
      last_sync_log_ms: nil,
      poll_generation: 0,
      # Per-protocol client conversations:
      # %{protocol => %{module, driver_state, items, connectivity}}.
      # `driver_state` is the driver's opaque sync bookmark, reset when
      # the slot's driver module changes between polls; `items` is the
      # slot's last successful item list, carried through failed polls.
      clients: %{}
    }

    {:ok, schedule_poll(state, 0)}
  end

  @impl GenServer
  def handle_info({:poll, generation}, %{poll_generation: generation} = state) do
    ready? = Capabilities.download_client_ready?()
    state = if ready?, do: poll_and_broadcast(state), else: state

    delay = cadence_ms(map_size(state.subscribers), ready?, state.queue.connectivity)
    {:noreply, schedule_poll(state, delay)}
  end

  # A tick from a superseded schedule (the cycle was rescheduled when the
  # first subscriber registered) — ignore; exactly one chain stays live.
  def handle_info({:poll, _stale_generation}, state), do: {:noreply, state}

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
      first_watcher? = map_size(state.subscribers) == 0
      state = %{state | subscribers: Map.put(state.subscribers, pid, ref)}
      {:noreply, if(first_watcher?, do: poll_for_first_watcher(state), else: state)}
    end
  end

  # The pending tick was scheduled at the idle cadence (up to 30 s out).
  # Someone is watching now: poll immediately and restart the cycle at
  # the watched cadence; the generation bump retires the pending timer.
  defp poll_for_first_watcher(state) do
    if Capabilities.download_client_ready?() do
      state = poll_and_broadcast(state)
      delay = cadence_ms(map_size(state.subscribers), true, state.queue.connectivity)
      schedule_poll(state, delay)
    else
      state
    end
  end

  defp schedule_poll(state, delay) do
    generation = state.poll_generation + 1
    Process.send_after(self(), {:poll, generation}, delay)
    %{state | poll_generation: generation}
  end

  defp poll_and_broadcast(state) do
    ready_drivers =
      for {config, module} <- Dispatcher.drivers(),
          Capabilities.client_ready?(config.protocol),
          do: {config.protocol, module}

    case ready_drivers do
      [] -> mark_not_configured(state)
      drivers -> run_syncs(state, drivers)
    end
  end

  defp run_syncs(state, drivers) do
    now = DateTime.utc_now()

    outcomes =
      Enum.map(drivers, fn {protocol, module} ->
        {protocol, sync_client(client_for(state.clients, protocol, module), protocol, now)}
      end)

    clients = Map.new(outcomes, fn {protocol, {client, _tick}} -> {protocol, client} end)
    ticks = outcomes |> Enum.map(fn {_protocol, {_client, tick}} -> tick end) |> Enum.reject(&is_nil/1)
    any_success? = ticks != []

    # Merge in slot order (torrent first — `drivers` preserves
    # Dispatcher.drivers/0 order). Completed items are kept in the
    # snapshot but excluded from health classification.
    items = Enum.flat_map(outcomes, fn {_protocol, {client, _tick}} -> client.items end)
    {active, completed} = Enum.split_with(items, &(&1.state != :completed))

    {history, enriched} =
      HealthHistory.update(state.history, active, System.monotonic_time(:microsecond))

    last_sync_log_ms = log_sync_ticks(ticks, state.last_sync_log_ms)

    queue = %QueueState{
      items: enriched ++ completed,
      last_polled_at: now,
      last_successful_poll_at: if(any_success?, do: now, else: state.queue.last_successful_poll_at),
      connectivity: merge_connectivity(clients),
      client_connectivity: Map.new(clients, fn {protocol, client} -> {protocol, client.connectivity} end)
    }

    store_and_broadcast(queue)

    %{state | queue: queue, history: history, last_sync_log_ms: last_sync_log_ms, clients: clients}
  end

  # One driver's sync tick. Returns {client_state, tick | nil} — tick is
  # {movement?, summary} on success, nil on failure (the failed slot
  # keeps its last-known items and its grade carries the failure).
  defp sync_client(client, protocol, now) do
    case client.module.sync(client.driver_state) do
      {:ok, %SyncResult{} = result} ->
        {%{
           client
           | driver_state: result.driver_state,
             items: result.items,
             connectivity: Connectivity.poll_succeeded(client.connectivity)
         }, {result.movement?, result.summary}}

      {:error, reason, next_driver_state} ->
        # The outage condition is owned by Downloads.IncidentContext.assess/0
        # (it reads the connectivity graded just below) — console-only, no
        # duplicate :log incident (ADR-054). The driver hands back the
        # bookmark to carry forward (it resets its own conversation so the
        # next successful poll is a full update).
        Log.warning(
          :library,
          "queue monitor poll failed (#{protocol}): #{inspect(reason)}",
          mc_incident: :skip
        )

        {%{
           client
           | driver_state: next_driver_state,
             connectivity: Connectivity.poll_failed(client.connectivity, classify_error(reason), now)
         }, nil}
    end
  end

  # A driver swap (user reconfigured the slot's client type) invalidates
  # the old driver's opaque bookmark — start its conversation fresh.
  defp client_for(clients, protocol, module) do
    case Map.get(clients, protocol) do
      %{module: ^module} = client ->
        client

      _new_or_swapped ->
        %{module: module, driver_state: nil, items: [], connectivity: Connectivity.initial()}
    end
  end

  # Worst grade across slots — a true "needs attention" roll-up for
  # consumers that render one indicator. Per-slot truth lives in
  # `client_connectivity`.
  defp merge_connectivity(clients) when map_size(clients) == 0, do: :not_configured

  defp merge_connectivity(clients) do
    grades = clients |> Map.values() |> Enum.map(& &1.connectivity)

    Enum.find(grades, &(&1 == :auth_failed)) ||
      Enum.find(grades, &match?({:offline, _}, &1)) ||
      Enum.find(grades, &match?({:transient_failure, _}, &1)) ||
      Enum.find(grades, &(&1 == :live)) ||
      :initializing
  end

  defp mark_not_configured(state) do
    queue = %QueueState{
      items: [],
      last_polled_at: DateTime.utc_now(),
      last_successful_poll_at: state.queue.last_successful_poll_at,
      connectivity: :not_configured,
      client_connectivity: %{}
    }

    store_and_broadcast(queue)
    %{state | queue: queue, history: %{}, clients: %{}}
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
  # but only for ticks worth seeing. Movement on ANY client logs all the
  # clients' summaries at :info immediately; steady-state echoes are
  # skipped except for a periodic heartbeat so the Console ring buffer
  # isn't flooded (see @sync_log_heartbeat_ms). Movement detection and
  # each line body come from the drivers (each knows its own delta
  # format); the cadence policy lives here. Returns the monotonic ms of
  # the last logged line so the caller can thread the heartbeat clock.
  defp log_sync_ticks([], last_log_ms), do: last_log_ms

  defp log_sync_ticks(ticks, last_log_ms) do
    movement? = Enum.any?(ticks, fn {moved?, _summary} -> moved? end)
    now_ms = System.monotonic_time(:millisecond)
    ms_since = if last_log_ms, do: now_ms - last_log_ms, else: @sync_log_heartbeat_ms

    case sync_log_level(movement?, ms_since) do
      :info ->
        line = Enum.map_join(ticks, " · ", fn {_moved?, summary} -> summary || "queue sync" end)
        Log.info(:acquisition, line)
        now_ms

      :skip ->
        last_log_ms
    end
  end
end
