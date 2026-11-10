defmodule MediaCentaur.Watcher.IgnoreRulesListener do
  @moduledoc """
  Reconciles what is recorded under the ignore rules when they change:
  `:exclude_dirs` / `:skip_dirs` on `Topics.config_updates()` →
  `Watcher.Rescan.retract_ignored/0`, on a task because it reads every
  presence row.

  Saving an ignore rule has to reconcile what is already recorded under it,
  or the user is left with rows they cannot see and cannot clear. Not gated
  on watching: the rule was saved, so the database must match it either
  way, and with watchers off nothing will re-add the rows — which is why
  this listener lives beside the watchers' FlagSupervisor, not among the
  flag's children. Each watcher refreshes its own cached rule set from the
  same broadcast; the retraction is the once-per-change, cross-directory
  half. The media-dir half of config listening is
  `Watcher.Dirs.Controller`, alive only while watching is on.
  """
  use GenServer

  alias MediaCentaur.Watcher.Rescan

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  # Test-only sync point: any prior `:config_updated` message in this
  # process's mailbox is guaranteed processed — its retraction task started
  # — before the call returns.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(_) do
    :ok = MediaCentaur.Settings.Config.subscribe()
    {:ok, nil}
  end

  @impl true
  def handle_info({:config_updated, key, _value}, state) when key in [:exclude_dirs, :skip_dirs] do
    Rescan.retract_ignored_async()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
