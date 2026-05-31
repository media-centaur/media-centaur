defmodule MediaCentaur.ErrorReports.Buckets do
  @moduledoc """
  GenServer that serves the Status page a fast, in-memory **cache over the
  durable incident store**.

  - On boot it rebuilds the cache from `Store.list_incidents/1` (the
    `:warning`/`:error` `:log` incidents), so a restart no longer loses
    evidence — the central guarantee of the observability backbone.
  - It subscribes to `Topics.console_logs()` and, for every `:warning`/`:error`
    entry, **persists durably via `Capture.persist_entry/1`** and folds the
    entry into the in-memory cache. The durable write is the source of truth;
    the cache is a projection rebuilt from it on the next boot.
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

  alias MediaCentaur.Console
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.BucketCache
  alias MediaCentaur.ErrorReports.Capture
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Topics

  @broadcast_throttle_ms 1_000
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

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    Console.subscribe()

    {:ok,
     %{
       cache: rebuild_from_store(),
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
  def handle_cast({:ingest, %Entry{level: level} = entry}, state) when level in @captured_levels do
    {:noreply, handle_entry(state, entry)}
  end

  @impl true
  def handle_cast({:ingest, _other}, state), do: {:noreply, state}

  @impl true
  def handle_info({:log_entry, %Entry{level: level} = entry}, state) when level in @captured_levels do
    {:noreply, handle_entry(state, entry)}
  end

  @impl true
  def handle_info({:log_entry, _other}, state), do: {:noreply, state}

  @impl true
  def handle_info(:flush_broadcast, state) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.error_reports(),
      {:buckets_changed, BucketCache.to_list(state.cache)}
    )

    {:noreply, %{state | last_broadcast_at: now_ms(), broadcast_pending: false}}
  end

  @impl true
  def handle_info(_other, state), do: {:noreply, state}

  # --- Internals ---

  defp handle_entry(state, %Entry{} = entry) do
    if test_env_noise?(entry) do
      state
    else
      _ = safe_persist(entry)

      schedule_broadcast(%{state | cache: BucketCache.put_entry(state.cache, entry)})
    end
  end

  # The durable write is intentionally fire-and-forget from the cache's point of
  # view: a failed/raised persistence must not crash logging or the cache. We do
  # NOT log the failure — that log line would re-enter this very handler and
  # could loop. Phase 2's diagnostics self-monitoring will surface a degraded
  # store as a `:subsystem` incident; until then the cache stays live and the
  # store reconciles on the next boot.
  defp safe_persist(%Entry{} = entry) do
    Capture.persist_entry(entry)
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
    |> Enum.map(fn incident ->
      samples =
        incident.fingerprint
        |> Store.list_recent_events(BucketCache.max_sample_entries())
        |> Enum.map(&%{timestamp: &1.occurred_at, message: &1.message})

      {incident, samples}
    end)
    |> BucketCache.from_incidents()
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
