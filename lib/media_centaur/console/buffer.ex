defmodule MediaCentaur.Console.Buffer do
  @moduledoc """
  A GenServer holding one capped ring of log entries **per component**.

  A single shared ring let a chatty component evict every other component's
  history — `:ecto` emits on the order of a thousand SQL debug lines an hour,
  so filtering the console to `:watcher` showed almost nothing. Each component
  now gets its own ring of `cap` entries, so one subsystem's volume cannot
  crowd out another's.

  `read/2` is the only way entries leave the store. It takes a `%Filter{}` and
  a limit, and uses the filter's component and level dimensions as a read
  selector: only visible rings are pulled, below-floor entries never leave, and
  the surviving entries merge newest-first by id. `config/0` reports the cap
  and filter separately.

  This is the runtime state of the console. The buffer cap and filter are
  persisted to `MediaCentaur.Settings` with a debounce to avoid excessive DB writes.

  All LiveViews and cross-context callers interact with the console through
  `MediaCentaur.Console` — never with this module directly.
  """
  use GenServer

  alias MediaCentaur.Console.{Entry, Filter}
  alias MediaCentaur.Log.Component
  alias MediaCentaur.Settings
  alias MediaCentaur.Topics

  @default_cap 200
  @min_cap 100
  @max_cap 1_000
  @persist_debounce_ms 2_000

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Fire-and-forget append. Safe to call when the buffer is not yet started."
  @spec append(Entry.t()) :: :ok
  def append(%Entry{} = entry), do: append(entry, __MODULE__)

  @doc "Explicit name variant for tests."
  @spec append(Entry.t(), atom()) :: :ok
  def append(%Entry{} = entry, name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:append, entry})
    end
  end

  @doc """
  Flushes any pending batched entries immediately, cancelling the scheduled
  flush timer. Synchronous — returns only after the `{:log_entries, _}`
  broadcast has been sent. Lets callers (and tests) force the batch out on
  demand instead of waiting on the ~100ms window; a no-op when nothing is
  pending.
  """
  @spec flush(atom()) :: :ok
  def flush(name \\ __MODULE__), do: GenServer.call(name, :flush)

  @doc """
  Entries matching `filter`, newest-first, capped at `limit`.

  The filter's component and level dimensions act as a **read selector** — only
  visible rings are pulled, and below-floor entries never leave the store. Search
  is not applied here: it is per-keystroke and handled at the call site.
  """
  @spec read(Filter.t(), non_neg_integer()) :: [Entry.t()]
  def read(%Filter{} = filter, limit), do: read(filter, limit, __MODULE__)

  @doc "Explicit name variant for tests."
  @spec read(Filter.t(), non_neg_integer(), atom()) :: [Entry.t()]
  def read(%Filter{} = filter, limit, name) when is_integer(limit) and limit >= 0 do
    GenServer.call(name, {:read, filter, limit})
  end

  @doc "The buffer's current cap (per component) and filter."
  @spec config() :: %{cap: pos_integer(), filter: Filter.t()}
  def config, do: config(__MODULE__)

  @doc "Explicit name variant for tests."
  @spec config(atom()) :: %{cap: pos_integer(), filter: Filter.t()}
  def config(name), do: GenServer.call(name, :config)

  @doc "Clears all entries from the buffer."
  @spec clear() :: :ok
  def clear, do: clear(__MODULE__)

  @doc "Explicit name variant for tests."
  @spec clear(atom()) :: :ok
  def clear(name) do
    GenServer.call(name, :clear)
  end

  @doc """
  Puts the buffer at rest: clears it and drops a pending settings write.
  The test harness's reset (`MediaCentaur.GlobalStateSandbox`): a resize
  or filter change arms a #{@persist_debounce_ms}ms debounce that would
  otherwise fire inside a later test's sandbox. `clear/1` keeps the
  pending write on purpose — a person emptying the console has not
  changed their mind about its size.
  """
  @spec reset(atom()) :: :ok
  def reset(name \\ __MODULE__), do: GenServer.call(name, :reset)

  @doc "Maximum allowed buffer cap. Used by LiveViews to size the stream once."
  @spec max_cap() :: pos_integer()
  def max_cap, do: @max_cap

  @doc "Minimum allowed buffer cap."
  @spec min_cap() :: pos_integer()
  def min_cap, do: @min_cap

  @doc "Default buffer cap used when no persisted setting exists."
  @spec default_cap() :: pos_integer()
  def default_cap, do: @default_cap

  @doc "Resizes the buffer cap. Must be between #{@min_cap} and #{@max_cap}."
  @spec resize(non_neg_integer()) :: :ok | {:error, String.t()}
  def resize(n), do: resize(n, __MODULE__)

  @doc "Explicit name variant for tests."
  @spec resize(non_neg_integer(), atom()) :: :ok | {:error, String.t()}
  def resize(n, name) when is_integer(n) do
    if n in @min_cap..@max_cap do
      GenServer.call(name, {:resize, n})
    else
      {:error, "cap must be between #{@min_cap} and #{@max_cap}, got #{n}"}
    end
  end

  @doc "Updates the active filter. Persists asynchronously."
  @spec put_filter(Filter.t()) :: :ok
  def put_filter(%Filter{} = filter), do: put_filter(filter, __MODULE__)

  @doc "Explicit name variant for tests."
  @spec put_filter(Filter.t(), atom()) :: :ok
  def put_filter(%Filter{} = filter, name) do
    GenServer.call(name, {:put_filter, filter})
  end

  @doc "Returns the current filter."
  @spec get_filter() :: Filter.t()
  def get_filter, do: get_filter(__MODULE__)

  @doc "Explicit name variant for tests."
  @spec get_filter(atom()) :: Filter.t()
  def get_filter(name) do
    GenServer.call(name, :get_filter)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    {settings_cap, filter} = load_settings()

    # opts[:cap] overrides the persisted cap — used in tests to set a small cap.
    # No floor/ceiling enforcement here; tests intentionally use values outside
    # the production range. The public resize/1 API enforces the range for callers.
    cap =
      case Keyword.get(opts, :cap) do
        override when is_integer(override) and override > 0 -> override
        _ -> settings_cap
      end

    state = %{
      rings: %{},
      overflow: %{},
      cap: cap,
      filter: filter,
      persist_ref: nil,
      # opts[:persist_debounce_ms] shortens the settings-persist debounce —
      # used in tests so the timer fires inside the test that armed it.
      persist_debounce_ms: Keyword.get(opts, :persist_debounce_ms, @persist_debounce_ms),
      pending: [],
      flush_ref: nil
    }

    {:ok, state}
  end

  # Appends broadcast as `{:log_entries, entries}` batches on a short
  # flush window rather than one `{:log_entry, _}` per line: every
  # connected page holds the (hidden) console drawer, so a navigation's
  # own burst of debug/SQL lines was costing one WS frame + one DOM
  # insert per line on every open page while that navigation was in
  # flight (campaigns/instant-navigation.md Phase 5). The buffer itself
  # is updated immediately — only the broadcast batches.
  #
  # Each component gets its own capped ring, so a chatty component (`:ecto`
  # emits ~1000 SQL debug lines an hour) cannot evict a quiet one's history.
  @impl true
  def handle_cast({:append, entry}, state) do
    component = ring_key(entry.component)
    ring = Map.get(state.rings, component, [])

    state = %{
      state
      | rings: Map.put(state.rings, component, [entry | ring]),
        pending: [entry | state.pending]
    }

    {:noreply, state |> trim_if_over(component) |> schedule_flush()}
  end

  # Rings key on the known component vocabulary. `Entry.from_log_event/3`
  # lets an explicit `meta[:component]` through as an arbitrary atom, so
  # without this fold the ring count would be unbounded. Anything
  # unrecognised joins :system, which is already the catch-all everywhere else.
  defp ring_key(component) do
    if component in Component.all(), do: component, else: :system
  end

  # Trimming on every append walked `cap` entries per log line (audit P8).
  # Each ring may run over by up to a quarter and is trimmed once per that
  # many appends; every read takes the cap, so the overflow is never observable.
  defp trim_if_over(state, component) do
    seen = Map.get(state.overflow, component, 0) + 1

    if seen >= max(div(state.cap, 4), 1) do
      ring = state.rings |> Map.fetch!(component) |> Enum.take(state.cap)

      %{
        state
        | rings: Map.put(state.rings, component, ring),
          overflow: Map.put(state.overflow, component, 0)
      }
    else
      %{state | overflow: Map.put(state.overflow, component, seen)}
    end
  end

  @impl true
  def handle_call({:read, filter, limit}, _from, state) do
    entries =
      state.rings
      |> Enum.filter(fn {component, _ring} -> Filter.component_visible?(filter, component) end)
      |> Enum.flat_map(fn {_component, ring} -> Enum.take(ring, state.cap) end)
      |> Enum.filter(&Filter.level_passes?(&1, filter))
      # Entry ids come from System.unique_integer([:monotonic, :positive]), so a
      # descending id sort is exact global recency across rings.
      |> Enum.sort_by(& &1.id, :desc)
      |> Enum.take(limit)

    {:reply, entries, state}
  end

  def handle_call(:config, _from, state) do
    {:reply, %{cap: state.cap, filter: state.filter}, state}
  end

  def handle_call(:clear, _from, state) do
    # Drop the unflushed batch too — flushing it after the clear would
    # resurrect rows the UI just emptied.
    if state.flush_ref, do: Process.cancel_timer(state.flush_ref)
    broadcast(:buffer_cleared)
    {:reply, :ok, %{state | rings: %{}, overflow: %{}, pending: [], flush_ref: nil}}
  end

  def handle_call(:reset, from, state) do
    if state.persist_ref, do: Process.cancel_timer(state.persist_ref)
    handle_call(:clear, from, %{state | persist_ref: nil})
  end

  def handle_call({:resize, n}, _from, state) do
    rings = Map.new(state.rings, fn {component, ring} -> {component, Enum.take(ring, n)} end)
    new_state = %{state | cap: n, rings: rings, overflow: %{}}
    broadcast({:buffer_resized, n})
    {:reply, :ok, schedule_persist(new_state)}
  end

  def handle_call({:put_filter, filter}, _from, state) do
    new_state = %{state | filter: filter}
    broadcast({:filter_changed, filter})
    new_state = schedule_persist(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_filter, _from, state) do
    {:reply, state.filter, state}
  end

  def handle_call(:flush, _from, state) do
    if state.flush_ref, do: Process.cancel_timer(state.flush_ref)
    {:reply, :ok, flush_pending(state)}
  end

  @impl true
  def handle_info(:flush_logs, state), do: {:noreply, flush_pending(state)}

  def handle_info(:persist, state) do
    try do
      persist_to_settings(state)
    rescue
      error ->
        require Logger

        # Tag with mc_log_source: :buffer so Console.Handler's reentrancy guard
        # drops this entry — otherwise a persist failure would recursively
        # self-document into the same buffer that just failed to persist.
        Logger.warning(
          "Console.Buffer: failed to persist settings: #{inspect(error)}",
          mc_log_source: :buffer
        )
    end

    {:noreply, %{state | persist_ref: nil}}
  end

  # --- Private helpers ---

  @flush_ms 100

  defp schedule_flush(%{flush_ref: nil} = state) do
    %{state | flush_ref: Process.send_after(self(), :flush_logs, @flush_ms)}
  end

  defp schedule_flush(state), do: state

  # Broadcast the pending batch (if any) and clear the flush window. Shared by
  # the timer path (`:flush_logs`) and the on-demand `flush/1` call.
  defp flush_pending(%{pending: []} = state), do: %{state | flush_ref: nil}

  defp flush_pending(state) do
    broadcast({:log_entries, Enum.reverse(state.pending)})
    %{state | pending: [], flush_ref: nil}
  end

  defp schedule_persist(state) do
    if state.persist_ref do
      Process.cancel_timer(state.persist_ref)
    end

    ref = Process.send_after(self(), :persist, state.persist_debounce_ms)
    %{state | persist_ref: ref}
  end

  defp broadcast(message) do
    Topics.publish(Topics.console_logs(), message)
  end

  defp load_settings do
    cap =
      case Settings.get_by_key("console_lines_per_component") do
        %{value: %{"value" => value}} when is_integer(value) ->
          if value in @min_cap..@max_cap, do: value, else: @default_cap

        _ ->
          @default_cap
      end

    filter =
      case Settings.get_by_key("console_filter") do
        %{value: value} when is_map(value) ->
          Filter.from_persistable(value)

        _ ->
          Filter.new_with_defaults()
      end

    {cap, filter}
  rescue
    _ -> {@default_cap, Filter.new_with_defaults()}
  end

  defp persist_to_settings(state) do
    Settings.find_or_create_entry!(%{
      key: "console_lines_per_component",
      value: %{"value" => state.cap}
    })

    Settings.find_or_create_entry!(%{
      key: "console_filter",
      value: Filter.to_persistable(state.filter)
    })
  end
end
