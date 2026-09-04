defmodule MediaCentaur.HttpClient.Cache.Coordinator do
  @moduledoc """
  Owns the response-cache table, runs single-flight, and sweeps.

  Reads never come here: `MediaCentaur.HttpClient.Cache` looks entries
  up in the named ETS table directly. Three things do come here:

    * **Claiming a key.** The first caller that needs the network for a
      key becomes its *leader* and gets `:leader` back. Callers that
      arrive while the leader is in flight park in the call until the
      leader reports, then get the leader's response (`{:done,
      response}`) or its failure (`{:failed, exception}`). The leader
      is monitored; if it dies mid-flight its followers fail rather
      than hang.
    * **Reporting.** The leader's response step reports `done/4` with
      the entry to store (or `nil` when the response was not
      cacheable); its error step reports `failed/3`.
    * **Retention.** Every `sweep_interval_ms` the table drops entries
      older than `retention_ms` (stale entries are kept that long so
      their ETag stays usable). After every insert the table is held
      under `max_entries` by evicting the oldest.

  The table is `:protected`: only this process writes, every process
  reads. Started once under `MediaCentaur.HttpClient.Supervisor` in dev
  and prod; not started under test, where cache tests start their own
  under a unique `name` and the rest of the suite runs uncached.
  """
  use GenServer

  alias MediaCentaur.HttpClient.Cache.Entry

  @default_max_entries 1_000
  @default_retention_ms to_timeout(week: 1)
  @default_sweep_interval_ms to_timeout(hour: 1)
  @default_claim_timeout_ms to_timeout(minute: 2)

  @type name :: atom()

  # --- Public API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "True when the coordinator (and so the table) named `name` is running."
  @spec running?(name()) :: boolean()
  def running?(name), do: :ets.whereis(name) != :undefined

  @doc "Number of stored entries, `0` when not running."
  @spec entry_count(name()) :: non_neg_integer()
  def entry_count(name) do
    case :ets.info(name, :size) do
      :undefined -> 0
      size -> size
    end
  end

  @doc "The stored entry for `key`, or `nil`."
  @spec lookup(name(), term()) :: Entry.t() | nil
  def lookup(name, key) do
    case :ets.lookup(name, key) do
      [{^key, %Entry{} = entry}] -> entry
      [] -> nil
    end
  end

  @doc """
  Claims `key`. `:leader` means the caller must make the request and
  report back; `{:done, response}` and `{:failed, exception}` are a
  leader's outcome, delivered to a caller that waited for it.
  """
  @spec claim(name(), term(), timeout()) ::
          :leader | {:done, Req.Response.t()} | {:failed, Exception.t()}
  def claim(name, key, timeout \\ @default_claim_timeout_ms) do
    GenServer.call(name, {:claim, key}, timeout)
  catch
    :exit, {:timeout, _} ->
      {:failed, %RuntimeError{message: "timed out waiting for the in-flight request"}}
  end

  @doc "The leader reports its response; `entry` is stored when not `nil`."
  @spec done(name(), term(), Req.Response.t(), Entry.t() | nil) :: :ok
  def done(name, key, response, entry) do
    GenServer.call(name, {:done, key, response, entry})
  catch
    :exit, _ -> :ok
  end

  @doc "The leader reports a transport failure."
  @spec failed(name(), term(), Exception.t()) :: :ok
  def failed(name, key, exception) do
    GenServer.call(name, {:failed, key, exception})
  catch
    :exit, _ -> :ok
  end

  @doc "Runs the retention sweep now."
  @spec sweep(name()) :: :ok
  def sweep(name), do: GenServer.call(name, :sweep)

  # --- Callbacks ---

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    :ets.new(name, [:named_table, :set, :protected, read_concurrency: true])

    state = %{
      table: name,
      in_flight: %{},
      max_entries: Keyword.get(opts, :max_entries, @default_max_entries),
      retention_ms: Keyword.get(opts, :retention_ms, @default_retention_ms),
      sweep_interval_ms: Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)
    }

    Process.send_after(self(), :sweep, state.sweep_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:claim, key}, {pid, _tag} = from, state) do
    case Map.fetch(state.in_flight, key) do
      {:ok, flight} ->
        flight = %{flight | waiters: [from | flight.waiters]}
        {:noreply, put_in(state.in_flight[key], flight)}

      :error ->
        flight = %{leader: pid, monitor: Process.monitor(pid), waiters: []}
        {:reply, :leader, put_in(state.in_flight[key], flight)}
    end
  end

  def handle_call({:done, key, response, entry}, _from, state) do
    if entry, do: insert(state, entry)
    {:reply, :ok, settle(state, key, {:done, response})}
  end

  def handle_call({:failed, key, exception}, _from, state) do
    {:reply, :ok, settle(state, key, {:failed, exception})}
  end

  def handle_call(:sweep, _from, state) do
    do_sweep(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Enum.find(state.in_flight, fn {_key, flight} -> flight.monitor == monitor end) do
      {key, _flight} ->
        exception = %RuntimeError{message: "the in-flight request's process exited"}
        {:noreply, settle(state, key, {:failed, exception})}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(:sweep, state) do
    do_sweep(state)
    Process.send_after(self(), :sweep, state.sweep_interval_ms)
    {:noreply, state}
  end

  # --- Internals ---

  defp settle(state, key, outcome) do
    case Map.pop(state.in_flight, key) do
      {nil, _in_flight} ->
        state

      {flight, in_flight} ->
        Process.demonitor(flight.monitor, [:flush])
        Enum.each(flight.waiters, &GenServer.reply(&1, outcome))
        %{state | in_flight: in_flight}
    end
  end

  defp insert(state, %Entry{} = entry) do
    :ets.insert(state.table, {entry.key, entry})
    surplus = :ets.info(state.table, :size) - state.max_entries

    if surplus > 0 do
      state.table
      |> oldest_first()
      |> Enum.take(surplus)
      |> Enum.each(fn {_stored_at, key} -> :ets.delete(state.table, key) end)
    end
  end

  defp oldest_first(table) do
    table
    |> :ets.tab2list()
    |> Enum.map(fn {key, %Entry{stored_at: stored_at}} -> {stored_at, key} end)
    |> Enum.sort()
  end

  defp do_sweep(state) do
    cutoff = System.monotonic_time(:millisecond) - state.retention_ms

    :ets.foldl(
      fn {key, %Entry{stored_at: stored_at}}, :ok ->
        if stored_at <= cutoff, do: :ets.delete(state.table, key)
        :ok
      end,
      :ok,
      state.table
    )
  end
end
