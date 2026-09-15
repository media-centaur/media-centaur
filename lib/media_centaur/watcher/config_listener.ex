defmodule MediaCentaur.Watcher.ConfigListener do
  @moduledoc """
  Bridges `Topics.config_updates()` to the watcher subsystem: the two
  config changes the subsystem has to act on, and nothing else.

  - **`:media_dirs`** → `Watcher.Supervisor.reconcile/1`, synchronous
    and idempotent. Only while watching is on
    (`Watcher.Supervisor.enabled?/0`): with watchers off — the service
    flag at boot, or the Settings toggle — a media-dir edit starts
    nothing. Turning them back on
    (`Watcher.Supervisor.start_watchers/0`) reads the current dirs, so
    nothing is lost in between.
  - **`:exclude_dirs` / `:skip_dirs`** → `Watcher.Rescan.retract_ignored/0`.
    Saving an ignore rule has to reconcile what is already recorded
    under it, or the user is left with rows they cannot see and cannot
    clear. Run on a task because it reads every presence row, and
    *not* gated on watching: the rule was saved, so the database must
    match it either way, and with watchers off nothing will re-add the
    rows.

  Each watcher refreshes its own cached rule set from the same
  broadcast; the retraction is the once-per-change, cross-directory
  half, which is why it lives here rather than in each watcher.
  """
  use GenServer

  alias MediaCentaur.Watcher
  alias MediaCentaur.Watcher.Rescan

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

  def handle_info({:config_updated, key, _value}, state) when key in [:exclude_dirs, :skip_dirs] do
    Rescan.retract_ignored_async()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
