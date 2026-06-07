defmodule MediaCentaur.ErrorReports.Buckets do
  @moduledoc """
  GenServer that serves the Status page a fast, in-memory **cache over the
  durable incident store**.

  - On boot it rebuilds the cache from `Store.list_incidents/1` (the
    `:warning`/`:error` `:log` incidents), so a restart no longer loses
    evidence — the central guarantee of the observability backbone.
  - It is fed by `ErrorReports.LogHandler` — an **independent** `:logger`
    handler, a peer of `Console.Handler`, not downstream of the volatile
    Console buffer — which casts each captured entry here via `ingest/2`. For
    every entry it **persists durably via `Capture.persist_entry/2`** and folds
    the entry into the in-memory cache. The durable write is the source of
    truth; the cache is a projection rebuilt from it on the next boot.
  - It broadcasts on `Topics.error_reports()` at most once per second.

  There is no time-based eviction: incidents are durable and the list is not
  windowed (retention is the store's prune job, not the cache's). The cache
  holds the most-recently-active buckets as a working set
  (`BucketCache.max_active_buckets/0`); older incidents live in the store and
  surface in the Phase 4 dashboard.

  Volatile (Console) and durable (this cache + store) paths stay independent: a
  persistence failure is swallowed here (see `safe_persist/1`) so it can never
  crash logging, and the cache still reflects the live entry — the store
  reconciles on the next boot.

  All grouping rules live in the pure `BucketCache`; this module is the wiring
  (subscribe, persist, throttle, broadcast). Public API (per ADR-026):
  `list_buckets/0`, `get_bucket/1`, `ingest/2` (exposed for tests; in
  production `ingest` is the `handle_info/2` path that receives PubSub
  messages). Never call `:sys.get_state` or `GenServer.call` directly in tests.
  """

  use GenServer

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.BucketCache
  alias MediaCentaur.ErrorReports.Capture
  alias MediaCentaur.ErrorReports.Fingerprint
  alias MediaCentaur.ErrorReports.PersistThrottle
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Topics

  @broadcast_throttle_ms 1_000
  @persist_window_ms 1_000
  @captured_levels [:warning, :error]

  # --- Public API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec list_buckets() :: [Bucket.t()]
  @spec list_buckets(GenServer.server()) :: [Bucket.t()]
  def list_buckets(server \\ __MODULE__) do
    GenServer.call(server, :list_buckets)
  end

  @spec get_bucket(binary()) :: Bucket.t() | nil
  @spec get_bucket(GenServer.server(), binary()) :: Bucket.t() | nil
  def get_bucket(server \\ __MODULE__, fingerprint) when is_binary(fingerprint) do
    GenServer.call(server, {:get_bucket, fingerprint})
  end

  # Exposed for tests and for the Console handler that forwards entries.
  @spec ingest(GenServer.server(), Entry.t()) :: :ok
  def ingest(server \\ __MODULE__, %Entry{} = entry) do
    GenServer.cast(server, {:ingest, entry})
  end

  @doc """
  Dismisses the given fingerprints: permanently deletes each backing `:log`
  incident (and its diagnostic events) from the durable store, evicts the buckets
  from the in-memory cache, and broadcasts the new list immediately (a user
  action, not throttled).

  Dismiss honours the user's intent literally — the incident is *removed*, not
  marked `:resolved`. A resolved row would reload on the next cache rebuild and
  reappear, which is the "dismissed incidents come back" complaint. If the same
  fault later recurs, the LogHandler opens a *fresh* incident from the new
  evidence (`Store.upsert_log_incident/1`); dismiss never permanently silences a
  live fault, it only clears what has happened so far.
  """
  @spec dismiss(GenServer.server(), [binary()]) :: :ok
  def dismiss(server \\ __MODULE__, fingerprints) when is_list(fingerprints) do
    GenServer.call(server, {:dismiss, fingerprints})
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    # Trap exits so terminate/2 runs on a graceful supervisor shutdown and can
    # flush coalesced durable writes that haven't hit their periodic flush yet.
    Process.flag(:trap_exit, true)

    window = Keyword.get(opts, :persist_window_ms, @persist_window_ms)
    schedule_flush(window)

    {:ok,
     %{
       cache: rebuild_from_store(),
       throttle: PersistThrottle.new(),
       persist_window_ms: window,
       last_broadcast_at: now_ms() - @broadcast_throttle_ms,
       broadcast_pending: false
     }}
  end

  @impl true
  def handle_call(:list_buckets, _from, state) do
    {:reply, BucketCache.to_list(state.cache), state}
  end

  @impl true
  def handle_call({:get_bucket, fingerprint}, _from, state) do
    {:reply, BucketCache.get(state.cache, fingerprint), state}
  end

  @impl true
  def handle_call({:dismiss, fingerprints}, _from, state) do
    Enum.each(fingerprints, &purge_from_store/1)

    cache = Enum.reduce(fingerprints, state.cache, &BucketCache.delete(&2, &1))
    broadcast(cache)

    {:reply, :ok, %{state | cache: cache, last_broadcast_at: now_ms(), broadcast_pending: false}}
  end

  @impl true
  def handle_cast({:ingest, %Entry{level: level} = entry}, state) when level in @captured_levels do
    {:noreply, handle_entry(state, entry)}
  end

  @impl true
  def handle_cast({:ingest, _other}, state), do: {:noreply, state}

  @impl true
  def handle_info(:flush_broadcast, state) do
    broadcast(state.cache)
    {:noreply, %{state | last_broadcast_at: now_ms(), broadcast_pending: false}}
  end

  @impl true
  def handle_info(:flush_persist, state) do
    throttle = flush_pending(state.throttle, state.persist_window_ms)
    schedule_flush(state.persist_window_ms)
    {:noreply, %{state | throttle: throttle}}
  end

  @impl true
  def handle_info(_other, state), do: {:noreply, state}

  # Flush coalesced writes on graceful shutdown so a clean stop doesn't lose the
  # pending count. (A hard kill can't run this — the store still reconciles from
  # what was already persisted on the next boot.)
  @impl true
  def terminate(_reason, state) do
    flush_pending(state.throttle, state.persist_window_ms)
    :ok
  end

  # --- Internals ---

  defp broadcast(cache) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.error_reports(),
      {:buckets_changed, BucketCache.to_list(cache)}
    )
  end

  # Permanently delete the durable `:log` incident (and its events) behind a
  # dismissed bucket. A failed store write must not crash the cache (mirrors
  # safe_persist/2): the bucket is already evicted from the working set, and a
  # surviving row would simply be re-dismissed on the next attempt.
  defp purge_from_store(fingerprint) do
    Store.delete_incident_by_fingerprint(fingerprint)
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp flush_pending(throttle, window_ms) do
    {writes, throttle} = PersistThrottle.flush_due(throttle, now_ms(), window_ms)
    Enum.each(writes, fn {entry, occurrences} -> safe_persist(entry, occurrences) end)
    throttle
  end

  defp schedule_flush(window_ms), do: Process.send_after(self(), :flush_persist, window_ms)

  defp handle_entry(state, %Entry{} = entry) do
    if test_env_noise?(entry) do
      state
    else
      # The cache counts every occurrence (accurate live view); the durable
      # write is debounced per fingerprint so an error storm can't flood the
      # single SQLite writer. First occurrence persists now; bursts coalesce
      # into a count flushed by :flush_persist (and by terminate/2 on shutdown).
      %{key: fingerprint} = Fingerprint.fingerprint(entry.component, entry.message)

      {decision, throttle} =
        PersistThrottle.record(state.throttle, fingerprint, entry, now_ms(), state.persist_window_ms)

      if decision == :persist_now, do: safe_persist(entry, 1)

      schedule_broadcast(%{
        state
        | cache: BucketCache.put_entry(state.cache, entry),
          throttle: throttle
      })
    end
  end

  # The durable write is intentionally fire-and-forget from the cache's point of
  # view: a failed/raised persistence must not crash logging or the cache. We do
  # NOT log the failure — that log line would re-enter this very handler and
  # could loop. Phase 2's diagnostics self-monitoring will surface a degraded
  # store as a `:subsystem` incident; until then the cache stays live and the
  # store reconciles on the next boot.
  defp safe_persist(%Entry{} = entry, occurrences) do
    Capture.persist_entry(entry, occurrences)
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  # Rebuild the working set from the durable store, newest-active first. N+1 on
  # boot (one recent-events read per incident) but bounded by the cache cap and
  # one-time; SQLite reads are sub-ms.
  defp rebuild_from_store do
    [limit: BucketCache.max_active_buckets()]
    |> Store.list_incidents()
    |> Enum.map(fn incident -> {incident, samples_for(incident)} end)
    |> BucketCache.from_incidents()
  end

  # Only fingerprint-keyed incidents (`:log`) have recent events to reconstruct
  # samples from. `:subsystem`/`:user` incidents carry no fingerprint and don't
  # bucket (BucketCache.from_incidents drops them), so skip the per-incident
  # event read — a `fingerprint == nil` query is forbidden by Ecto and would
  # crash the boot rebuild.
  defp samples_for(%{fingerprint: nil}), do: []

  defp samples_for(%{fingerprint: fingerprint}) do
    fingerprint
    |> Store.list_recent_events(BucketCache.max_sample_entries())
    |> Enum.map(&%{timestamp: &1.occurred_at, message: &1.message})
  end

  defp schedule_broadcast(%{broadcast_pending: true} = state), do: state

  defp schedule_broadcast(state) do
    since_last = now_ms() - state.last_broadcast_at

    if since_last >= @broadcast_throttle_ms do
      send(self(), :flush_broadcast)
    else
      Process.send_after(self(), :flush_broadcast, @broadcast_throttle_ms - since_last)
    end

    %{state | broadcast_pending: true}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  # Drops the `Ecto.Adapters.SQL.Sandbox` owner-exit disconnect that fires when
  # a Task spawned during a test outlives its sandbox owner. The pattern only
  # occurs in the test environment; in production no Sandbox is in the path.
  # Bucketing it would surface as flake noise in unrelated tests
  # (see flaky-tests.md #2).
  defp test_env_noise?(%Entry{message: message}) do
    Application.get_env(:media_centaur, :environment) == :test and
      String.contains?(message, "DBConnection.ConnectionError") and
      String.contains?(message, "Sandbox")
  end
end
