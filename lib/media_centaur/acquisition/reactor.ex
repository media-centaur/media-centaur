defmodule MediaCentaur.Acquisition.Reactor do
  @moduledoc """
  GenServer that reacts to release-tracking PubSub events.

  Subscribes to `Topics.release_tracking_updates/0` and
  `Topics.acquisition_updates/0` and dispatches each domain event to
  `Acquisition.Reactor.Handlers`:

  - `{:release_ready, item, release}` — **ignored since the ADR-056
    cutover** (the drop planner below is the materialization path).
    The broadcast and the dormant `Handlers.release_ready/2` machinery
    are deleted in the convergence campaign's Phase 4 after soak.
  - `{:tracking_sweep_completed}` — the refresher's sweep finished a
    want-ledger sync pass. Runs the drop planner tick
    (`Handlers.tracking_sweep_completed/0`).
  - `%PlanEvents.Changed{status: "ready"}` — a plan finished solving.
    For tracking-born plans, `Handlers.plan_changed/1` applies the mode
    gate (auto-approve / leave for ask / drop empty drafts).
  - `{:item_removed, tmdb_id, tmdb_type}` — a tracked item was removed.
    Active (`seeking`) targets for that key are cancelled.

  Lives on the supervision tree as a pubsub_listener (see `Application`).
  Subscribe-and-dispatch only — all logic lives in `Handlers`.
  """

  use GenServer

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.CancelReasons
  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Reactor.Handlers
  alias MediaCentaur.Topics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.release_tracking_updates())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())
    {:ok, %{}}
  end

  @impl GenServer
  # ADR-056 cutover: the per-event arm path no longer fires — the drop
  # planner (tick below) is the materialization path. The broadcast
  # itself and `Handlers.release_ready/2` are deleted in Phase 4 of the
  # convergence campaign after the new pipeline has soaked.
  def handle_info({:release_ready, _item, _release}, state) do
    {:noreply, state}
  end

  def handle_info({:tracking_sweep_completed}, state) do
    Handlers.tracking_sweep_completed()
    {:noreply, state}
  end

  def handle_info(%PlanEvents.Changed{} = event, state) do
    Handlers.plan_changed(event)
    {:noreply, state}
  end

  def handle_info({:item_removed, tmdb_id, tmdb_type}, state) do
    Acquisition.cancel_active_targets_for(tmdb_id, tmdb_type, CancelReasons.item_removed())
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
