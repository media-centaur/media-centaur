defmodule MediaCentaur.Watcher.ConfigListener do
  @moduledoc """
  Subscribes to `Topics.config_updates()` and calls
  `Watcher.Supervisor.reconcile/1` on every media-dir change broadcast.

  Thin PubSub bridge — the reconcile itself is synchronous and idempotent.

  Only while watching is on (`Watcher.Supervisor.enabled?/0`): with
  watchers off — the service flag at boot, or the Settings toggle — a
  media-dir edit starts nothing. Turning them back on
  (`Watcher.Supervisor.start_watchers/0`) reads the current dirs, so
  nothing is lost in between.
  """
  use GenServer

  alias MediaCentaur.Watcher

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  # Test-only sync point: any prior `:config_updated` message in this
  # GenServer's mailbox is guaranteed processed before the call returns.
  # Lets tests drop `Process.sleep(150)` after a config push.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(_) do
    :ok = MediaCentaur.Settings.Config.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:config_updated, :media_dirs, entries}, state) do
    if Watcher.Supervisor.enabled?() do
      Watcher.Supervisor.reconcile(entries)
      Watcher.Supervisor.reconcile_image_dir_monitors()
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
