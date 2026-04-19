defmodule MediaCentarr.Watcher.ConfigListener do
  @moduledoc """
  Subscribes to `Topics.config_updates()` and calls
  `Watcher.Supervisor.reconcile/1` on every watch-dir change broadcast.

  Thin PubSub bridge — the reconcile itself is synchronous and idempotent.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ok = MediaCentarr.Config.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:config_updated, :watch_dirs, entries}, state) do
    MediaCentarr.Watcher.Supervisor.reconcile(entries)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
