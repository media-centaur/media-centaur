defmodule MediaCentarr.ErrorReports.Buckets do
  @moduledoc """
  GenServer that ingests Console `:error` entries, groups them by
  fingerprint, and serves a windowed snapshot to the Status page.

  - Subscribes to `Topics.console_logs()` on start and receives
    `{:log_entry, entry}` messages.
  - Each error entry is fingerprinted via `Fingerprint.fingerprint/2`,
    then appended to a `%Bucket{}` in `state.buckets`.
  - Broadcasts on `Topics.error_reports()` at most once per second.
  - Prunes buckets whose `last_seen` is outside the retention window
    every 60 seconds; `list_buckets/0` filters at call time so the UI
    is never more than the broadcast-throttle stale.

  Public API (per ADR-026): `list_buckets/0`, `get_bucket/1`, `ingest/2`
  (exposed for tests; in production `ingest` is invoked from the
  `handle_info/2` clause that receives PubSub messages). Never call
  `:sys.get_state` or `GenServer.call` directly in tests.
  """

  use GenServer
  require MediaCentarr.Log

  alias MediaCentarr.Console
  alias MediaCentarr.Console.Entry
  alias MediaCentarr.ErrorReports.{Bucket, Fingerprint}
  alias MediaCentarr.Topics

  @default_window_minutes 60
  @broadcast_throttle_ms 1_000
  @prune_interval_ms 60_000
  @max_sample_entries 5
  @max_active_buckets 200

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

  # Exposed for tests and for the Console handler that forwards errors.
  @spec ingest(GenServer.server(), Entry.t()) :: :ok
  def ingest(server \\ __MODULE__, %Entry{} = entry) do
    GenServer.cast(server, {:ingest, entry})
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    Console.subscribe()
    Process.send_after(self(), :prune, @prune_interval_ms)

    {:ok,
     %{
       buckets: %{},
       window_minutes: Keyword.get(opts, :window_minutes, @default_window_minutes),
       last_broadcast_at: now_ms() - @broadcast_throttle_ms,
       broadcast_pending: false
     }}
  end

  @impl true
  def handle_call(:list_buckets, _from, state) do
    {:reply, visible_buckets(state), state}
  end

  @impl true
  def handle_call({:get_bucket, fp}, _from, state) do
    bucket =
      state
      |> visible_buckets()
      |> Enum.find(&(&1.fingerprint == fp))

    {:reply, bucket, state}
  end

  @impl true
  def handle_cast({:ingest, %Entry{level: :error} = entry}, state) do
    if test_env_noise?(entry), do: {:noreply, state}, else: {:noreply, do_ingest(state, entry)}
  end

  @impl true
  def handle_cast({:ingest, _non_error}, state), do: {:noreply, state}

  @impl true
  def handle_info({:log_entry, %Entry{level: :error} = entry}, state) do
    if test_env_noise?(entry), do: {:noreply, state}, else: {:noreply, do_ingest(state, entry)}
  end

  @impl true
  def handle_info({:log_entry, _}, state), do: {:noreply, state}

  @impl true
  def handle_info(:prune, state) do
    Process.send_after(self(), :prune, @prune_interval_ms)
    cutoff = cutoff(state)

    new_buckets =
      Map.filter(state.buckets, fn {_, bucket} ->
        DateTime.after?(bucket.last_seen, cutoff)
      end)

    {:noreply, %{state | buckets: new_buckets}}
  end

  @impl true
  def handle_info(:flush_broadcast, state) do
    snapshot = visible_buckets(state)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.error_reports(),
      {:buckets_changed, snapshot}
    )

    {:noreply, %{state | last_broadcast_at: now_ms(), broadcast_pending: false}}
  end

  @impl true
  def handle_info(_other, state), do: {:noreply, state}

  # --- Internals ---

  defp do_ingest(state, %Entry{} = entry) do
    %{key: key, display_title: title, normalized_message: normalized} =
      Fingerprint.fingerprint(entry.component, entry.message)

    sample = %{
      timestamp: entry.timestamp,
      message: normalized
    }

    bucket =
      case Map.get(state.buckets, key) do
        nil ->
          %Bucket{
            fingerprint: key,
            component: entry.component,
            normalized_message: normalized,
            display_title: title,
            count: 1,
            first_seen: entry.timestamp,
            last_seen: entry.timestamp,
            sample_entries: [sample]
          }

        %Bucket{} = existing ->
          %{
            existing
            | count: existing.count + 1,
              last_seen: max_dt(existing.last_seen, entry.timestamp),
              first_seen: min_dt(existing.first_seen, entry.timestamp),
              sample_entries: take_samples([sample | existing.sample_entries])
          }
      end

    new_buckets =
      state.buckets
      |> Map.put(key, bucket)
      |> enforce_cap()

    schedule_broadcast(%{state | buckets: new_buckets})
  end

  defp visible_buckets(state) do
    cutoff = cutoff(state)

    state.buckets
    |> Map.values()
    |> Enum.filter(&DateTime.after?(&1.last_seen, cutoff))
    |> Enum.sort_by(& &1.last_seen, {:desc, DateTime})
  end

  defp cutoff(state) do
    DateTime.add(DateTime.utc_now(), -state.window_minutes * 60, :second)
  end

  defp take_samples(list), do: Enum.take(list, @max_sample_entries)

  defp enforce_cap(buckets) when map_size(buckets) <= @max_active_buckets, do: buckets

  defp enforce_cap(buckets) do
    {drop_key, _} =
      Enum.min_by(buckets, fn {_, bucket} ->
        DateTime.to_unix(bucket.last_seen, :microsecond)
      end)

    Map.delete(buckets, drop_key)
  end

  defp schedule_broadcast(%{broadcast_pending: true} = state), do: state

  defp schedule_broadcast(state) do
    since_last = now_ms() - state.last_broadcast_at

    if since_last >= @broadcast_throttle_ms do
      send(self(), :flush_broadcast)
      %{state | broadcast_pending: true}
    else
      Process.send_after(self(), :flush_broadcast, @broadcast_throttle_ms - since_last)
      %{state | broadcast_pending: true}
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp max_dt(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp min_dt(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

  # Drops the `Ecto.Adapters.SQL.Sandbox` owner-exit disconnect that fires when
  # a Task spawned during a test outlives its sandbox owner. The pattern only
  # occurs in the test environment; in production no Sandbox is in the path.
  # Bucketing it would surface as flake noise in unrelated tests
  # (see flaky-tests.md #2).
  defp test_env_noise?(%Entry{message: message}) do
    Application.get_env(:media_centarr, :environment) == :test and
      String.contains?(message, "DBConnection.ConnectionError") and
      String.contains?(message, "Sandbox")
  end
end
