defmodule MediaCentarr.Watcher.ConfigListener do
  @moduledoc """
  Subscribes to `Topics.config_updates()` and calls
  `Watcher.Supervisor.reconcile/1` on every watch-dir change broadcast.

  Thin PubSub bridge — the reconcile itself is synchronous and idempotent.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  # Test-only sync point: any prior `:config_updated` message in this
  # GenServer's mailbox is guaranteed processed before the call returns.
  # Lets tests drop `Process.sleep(150)` after a config push.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(_) do
    :ok = MediaCentarr.Config.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:config_updated, :watch_dirs, entries}, state) do
    MediaCentarr.Watcher.Supervisor.reconcile(entries)
    MediaCentarr.Watcher.Supervisor.reconcile_image_dir_monitors()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
