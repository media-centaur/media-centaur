defmodule MediaCentarr.Console.JournalSource do
  @moduledoc """
  Live `journalctl -f` tail as a peer log source to `Console.Buffer`.

  Owns a single `journalctl --user -u <unit> -n 200 -f --output=short-iso`
  subprocess — spawned via `Port.open` when the first subscriber joins,
  closed after a short debounce once the last one leaves.

  Emits one `{:journal_line, %Entry{}}` message per line on
  `Topics.service_journal()`. Entries reuse the shared `Console.Entry`
  struct with `component: :systemd` so the Console drawer's stream can
  render them with the same row component used for BEAM logs.

  ## Injectable spawner

  The `:port_opener` option accepts `(unit_name -> port() | pid())`. In
  production the default uses `Port.open/2`. Tests pass a helper pid that
  mimics Port message shape (`{port_or_pid, {:data, {:eol, line}}}` and
  `{port_or_pid, {:exit_status, code}}`) so nothing really shells out.
  """

  use GenServer

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Console.Entry
  alias MediaCentarr.SelfUpdate
  alias MediaCentarr.Topics

  @buffer_cap 500
  @debounce_close_ms 5_000
  @respawn_delay_ms 2_000
  @prime_line_count 200

  defmodule State do
    @moduledoc false
    defstruct subscribers: %{},
              port: nil,
              buffer: [],
              counter: 0,
              close_timer: nil,
              respawn_timer: nil,
              port_opener: nil,
              unit: nil
  end

  # --- Public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes the caller. Spawns the `journalctl` port on first subscriber.

  Returns:
    * `{:ok, [Entry.t()]}` — the current ring-buffer snapshot, newest-last.
    * `{:error, :no_unit_detected}` — the BEAM isn't under a systemd unit.
  """
  @spec subscribe(atom() | pid()) :: {:ok, [Entry.t()]} | {:error, :no_unit_detected}
  def subscribe(server \\ __MODULE__) do
    # PubSub.subscribe must be called from the LiveView's own process so
    # broadcasts land in its mailbox — not the GenServer's. Register the
    # caller with the GenServer first (cheap; fails fast if no unit); on
    # success, subscribe the caller to the broadcast topic.
    case GenServer.call(server, {:subscribe, self()}) do
      {:ok, snapshot} ->
        :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.service_journal())
        {:ok, snapshot}

      {:error, _} = error ->
        error
    end
  end

  @doc "Unsubscribes the caller. Port closes after a 5-second debounce when refcount hits zero."
  @spec unsubscribe(atom() | pid()) :: :ok
  def unsubscribe(server \\ __MODULE__) do
    _ = Phoenix.PubSub.unsubscribe(MediaCentarr.PubSub, Topics.service_journal())
    GenServer.call(server, {:unsubscribe, self()})
  end

  @doc "Force-closes and respawns the port immediately."
  @spec reconnect(atom() | pid()) :: :ok | {:error, :no_unit_detected | :no_subscribers}
  def reconnect(server \\ __MODULE__) do
    GenServer.call(server, :reconnect)
  end

  @doc "Returns true when a systemd unit has been detected and journalctl is reachable."
  @spec available?(atom() | pid()) :: boolean()
  def available?(server \\ __MODULE__) do
    GenServer.call(server, :available?)
  end

  @doc "Returns the current ring-buffer snapshot."
  @spec snapshot(atom() | pid()) :: [Entry.t()]
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  # --- GenServer callbacks ---

  @impl GenServer
  def init(opts) do
    # Unit detection is cheap (env + /proc/self/cgroup) and immutable
    # over the BEAM's lifetime — read it once at init and keep it in
    # state. This keeps `available?/0` a constant-time return from a
    # stored boolean, which matters because every LiveView mount in
    # the app calls it via `console_mount`.
    unit_fetcher = Keyword.get(opts, :unit_fetcher, &default_unit_fetcher/0)

    state = %State{
      port_opener: Keyword.get(opts, :port_opener, &default_port_opener/1),
      unit: unit_fetcher.()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, pid}, _from, %State{} = state) do
    case current_unit(state) do
      nil ->
        {:reply, {:error, :no_unit_detected}, state}

      _unit ->
        state = add_subscriber(state, pid)
        state = cancel_close_timer(state)
        state = ensure_port(state)
        {:reply, {:ok, Enum.reverse(state.buffer)}, state}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, %State{} = state) do
    state = remove_subscriber(state, pid)
    state = maybe_schedule_close(state)
    {:reply, :ok, state}
  end

  def handle_call(:reconnect, _from, %State{subscribers: subs} = state) when map_size(subs) == 0 do
    {:reply, {:error, :no_subscribers}, state}
  end

  def handle_call(:reconnect, _from, %State{} = state) do
    case current_unit(state) do
      nil ->
        {:reply, {:error, :no_unit_detected}, state}

      _unit ->
        state = close_port(state)
        broadcast({:journal_reset})
        state = ensure_port(state)
        {:reply, :ok, state}
    end
  end

  def handle_call(:available?, _from, %State{} = state) do
    {:reply, current_unit(state) != nil, state}
  end

  def handle_call(:snapshot, _from, %State{} = state) do
    {:reply, Enum.reverse(state.buffer), state}
  end

  @impl GenServer
  def handle_info({port, {:data, {:eol, line}}}, %State{port: port} = state) when port != nil do
    entry = build_entry(line, state.counter + 1)
    state = %{state | counter: state.counter + 1, buffer: cap_buffer([entry | state.buffer])}
    broadcast({:journal_line, entry})
    {:noreply, state}
  end

  def handle_info({port, {:data, {:noeol, _partial}}}, %State{port: port} = state) when port != nil do
    # Over-long lines are rare for journalctl short-iso output; ignore the
    # continuation rather than stitching — the next :eol will flush it.
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %State{port: port} = state) when port != nil do
    Log.warning(:system, "journalctl port exited with status #{code}; scheduling respawn")
    broadcast({:journal_reset})
    state = %{state | port: nil}
    state = schedule_respawn(state)
    {:noreply, state}
  end

  def handle_info(:respawn, %State{subscribers: subs} = state) when map_size(subs) > 0 do
    state = %{state | respawn_timer: nil}
    state = ensure_port(state)
    {:noreply, state}
  end

  def handle_info(:respawn, %State{} = state) do
    {:noreply, %{state | respawn_timer: nil}}
  end

  def handle_info(:close_port, %State{subscribers: subs} = state) when map_size(subs) == 0 do
    state = close_port(state)
    {:noreply, %{state | close_timer: nil, buffer: [], counter: 0}}
  end

  def handle_info(:close_port, %State{} = state) do
    # Subscribers came back during the debounce window — cancel the close.
    {:noreply, %{state | close_timer: nil}}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{subscribers: subs} = state) do
    case Map.get(subs, pid) do
      ^ref ->
        state = %{state | subscribers: Map.delete(subs, pid)}
        state = maybe_schedule_close(state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Helpers ---

  defp add_subscriber(%State{subscribers: subs} = state, pid) do
    case Map.get(subs, pid) do
      nil ->
        ref = Process.monitor(pid)
        %{state | subscribers: Map.put(subs, pid, ref)}

      _ref ->
        state
    end
  end

  defp remove_subscriber(%State{subscribers: subs} = state, pid) do
    case Map.pop(subs, pid) do
      {nil, _} -> state
      {ref, rest} -> %{state | subscribers: (Process.demonitor(ref, [:flush]) && rest) || rest}
    end
  end

  defp maybe_schedule_close(%State{subscribers: subs, close_timer: nil} = state)
       when map_size(subs) == 0 do
    timer = Process.send_after(self(), :close_port, @debounce_close_ms)
    %{state | close_timer: timer}
  end

  defp maybe_schedule_close(state), do: state

  defp cancel_close_timer(%State{close_timer: nil} = state), do: state

  defp cancel_close_timer(%State{close_timer: timer} = state) do
    _ = Process.cancel_timer(timer)
    %{state | close_timer: nil}
  end

  defp ensure_port(%State{port: port} = state) when not is_nil(port), do: state

  defp ensure_port(%State{} = state) do
    case current_unit(state) do
      nil ->
        state

      unit ->
        port = state.port_opener.(unit)
        %{state | port: port}
    end
  end

  defp close_port(%State{port: nil} = state), do: state

  defp close_port(%State{port: port} = state) do
    _ =
      try do
        if is_port(port), do: Port.close(port), else: :ok
      catch
        _, _ -> :ok
      end

    %{state | port: nil}
  end

  defp schedule_respawn(%State{respawn_timer: nil} = state) do
    timer = Process.send_after(self(), :respawn, @respawn_delay_ms)
    %{state | respawn_timer: timer}
  end

  defp schedule_respawn(state), do: state

  defp cap_buffer(buffer) when length(buffer) > @buffer_cap do
    Enum.take(buffer, @buffer_cap)
  end

  defp cap_buffer(buffer), do: buffer

  defp current_unit(%State{unit: unit}), do: unit

  defp build_entry(line, id) do
    Entry.new(%{
      id: id,
      timestamp: DateTime.utc_now(),
      level: :info,
      component: :systemd,
      message: to_string(line)
    })
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.service_journal(), message)
  end

  defp default_unit_fetcher, do: SelfUpdate.detected_unit()

  defp default_port_opener(unit) do
    path = System.find_executable("journalctl") || "/usr/bin/journalctl"

    Port.open({:spawn_executable, path}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      {:line, 4096},
      args: [
        "--user",
        "-u",
        unit,
        "-n",
        Integer.to_string(@prime_line_count),
        "-f",
        "--output=short-iso"
      ]
    ])
  end
end
