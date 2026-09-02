defmodule MediaCentaur.Friends.Connections.Owner do
  @moduledoc """
  The process that owns every relay connection: it reconciles the running
  set against the `relays` rows (on boot, and on `RelayAdded` /
  `RelayRemoved` / `IdentityChanged`), receives each connection's
  `{:nostr, url, message}`, keeps the status map, and re-broadcasts on
  `friends:connections` through `Friends.Events`.

  Two subscription maps are kept and re-applied whenever a connection
  starts: `subs` (every relay, from `subscribe_all/2`) and `relay_subs`
  (one relay, from `subscribe/3` — the recommendations sync publishes
  only what a given relay lacks, so fan-out is wrong there).
  """

  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Friends.Events
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Connection
  alias MediaCentaur.Nostr.Event

  # A terminated connection is unregistered by the Registry asynchronously
  # (it links to the registered process and cleans up on the EXIT signal),
  # so restarting the same URL immediately can collide with the stale key.
  # `stop/1` waits for the key to clear; in practice the first check passes.
  @unregister_wait_ms 1
  @unregister_tries 200

  defstruct status: %{}, subs: %{}, relay_subs: %{}, backoff_ms: 1_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The status map, or `%{}` when no owner is running."
  @spec status() :: %{optional(String.t()) => Connections.entry()}
  def status do
    case GenServer.whereis(__MODULE__) do
      nil -> %{}
      pid -> GenServer.call(pid, :status)
    end
  end

  @spec publish(Event.t()) :: :ok
  def publish(%Event{} = event), do: GenServer.cast(__MODULE__, {:publish, event})

  @spec publish(String.t(), Event.t()) :: :ok
  def publish(url, %Event{} = event), do: GenServer.cast(__MODULE__, {:publish, url, event})

  @spec subscribe_all(String.t(), [MediaCentaur.Nostr.Filter.t()]) :: :ok
  def subscribe_all(sub_id, filters), do: GenServer.cast(__MODULE__, {:subscribe_all, sub_id, filters})

  @spec subscribe(String.t(), String.t(), [MediaCentaur.Nostr.Filter.t()]) :: :ok
  def subscribe(url, sub_id, filters), do: GenServer.cast(__MODULE__, {:subscribe, url, sub_id, filters})

  @doc false
  def __sync_for_test__(server \\ __MODULE__), do: GenServer.call(server, :sync)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Friends.subscribe()
    {:ok, %__MODULE__{backoff_ms: Keyword.get(opts, :backoff_ms, 1_000)}, {:continue, :boot}}
  end

  @impl true
  def handle_continue(:boot, state), do: {:noreply, reconcile(state)}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_cast({:publish, event}, state) do
    for {url, %{state: :connected}} <- state.status, do: publish_to(url, event)
    {:noreply, state}
  end

  def handle_cast({:publish, url, event}, state) do
    case state.status do
      %{^url => %{state: :connected}} -> publish_to(url, event)
      _other -> :ok
    end

    {:noreply, state}
  end

  def handle_cast({:subscribe_all, sub_id, filters}, state) do
    for url <- Map.keys(state.status),
        do: with_connection(url, &Connection.subscribe(&1, sub_id, filters))

    {:noreply, %{state | subs: Map.put(state.subs, sub_id, filters)}}
  end

  def handle_cast({:subscribe, url, sub_id, filters}, state) do
    with_connection(url, &Connection.subscribe(&1, sub_id, filters))
    relay_subs = Map.update(state.relay_subs, url, %{sub_id => filters}, &Map.put(&1, sub_id, filters))
    {:noreply, %{state | relay_subs: relay_subs}}
  end

  @impl true
  def handle_info({:relay_added, _event}, state), do: {:noreply, reconcile(state)}
  def handle_info({:relay_removed, _event}, state), do: {:noreply, reconcile(state)}

  def handle_info({:identity_changed, _event}, state), do: {:noreply, state |> stop_all() |> reconcile()}

  def handle_info({:nostr, url, message}, state) do
    log_message(url, message)
    Events.broadcast_connection(url, message)

    status =
      Map.update(
        state.status,
        url,
        Connections.apply_message(Connections.blank_entry(), message),
        &Connections.apply_message(&1, message)
      )

    {:noreply, %{state | status: status}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_all(state)
    :ok
  end

  # A relay refusing what we published is the one connection message a user
  # cannot see coming; the status entry keeps it, the log keeps the history.
  defp log_message(url, {:ok, _id, false, reason}),
    do: Log.warning(:friends, "#{url} rejected a recommendation: #{reason}")

  defp log_message(_url, _message), do: :ok

  # --- reconcile ---------------------------------------------------------

  defp reconcile(state) do
    wanted =
      if Identity.present?(), do: MapSet.new(Friends.list_relays(), & &1.url), else: MapSet.new()

    running = MapSet.new(running_urls())

    Enum.each(MapSet.difference(running, wanted), &stop/1)
    Enum.each(MapSet.difference(wanted, running), &start(&1, state))

    %{state | status: Map.new(wanted, &{&1, Map.get(state.status, &1, Connections.blank_entry())})}
  end

  defp stop_all(state) do
    Enum.each(running_urls(), &stop/1)
    %{state | status: %{}}
  end

  # `{key, pid, value}` is the Registry's match shape; we only want the keys.
  defp running_urls, do: Registry.select(Connections.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])

  defp start(url, state) do
    spec =
      {Connection,
       url: url, owner: self(), signer: &sign/1, backoff_ms: state.backoff_ms, name: Connections.via(url)}

    case DynamicSupervisor.start_child(Connections.DynamicSupervisor, spec) do
      {:ok, pid} ->
        for {sub_id, filters} <- state.subs, do: Connection.subscribe(pid, sub_id, filters)

        for {sub_id, filters} <- Map.get(state.relay_subs, url, %{}),
            do: Connection.subscribe(pid, sub_id, filters)

        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Log.warning(:friends, "could not start relay connection #{url}: #{inspect(reason)}")
        :ok
    end
  end

  defp stop(url) do
    case Registry.lookup(Connections.Registry, url) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(Connections.DynamicSupervisor, pid)
        await_unregistered(url, @unregister_tries)

      [] ->
        :ok
    end
  end

  defp await_unregistered(url, 0) do
    Log.warning(:friends, "#{url} is still registered after being stopped; restarting it may collide")
    :ok
  end

  defp await_unregistered(url, tries) do
    case Registry.lookup(Connections.Registry, url) do
      [] ->
        :ok

      _still_there ->
        Process.sleep(@unregister_wait_ms)
        await_unregistered(url, tries - 1)
    end
  end

  defp publish_to(url, event), do: with_connection(url, &Connection.publish(&1, event))

  defp with_connection(url, fun) do
    case Registry.lookup(Connections.Registry, url) do
      [{pid, _value}] -> fun.(pid)
      [] -> :ok
    end

    :ok
  end

  defp sign(%Event{} = event), do: Event.sign(event, Identity.secret())
end
