defmodule MediaCentaur.Acquisition.Reactor do
  @moduledoc """
  GenServer that reacts to release-tracking PubSub events.

  Subscribes to `Topics.release_tracking_updates/0` and
  `Topics.acquisition_updates/0` and dispatches each domain event to
  `Acquisition.Reactor.Handlers`:

  - `{:release_ready, item, release}` — a tracked release is now available.
    Routed through `Handlers.release_ready/2`, which asks
    `AutoGrabPolicy.decide/3` whether to enqueue, skip, or cancel. The
    capability gate is enforced inside the policy — when Prowlarr is
    not configured, the message is dropped. *(Legacy path — retires with
    the ADR-056 cutover; the drop planner below replaces it.)*
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
  def handle_info({:release_ready, item, release}, state) do
    Handlers.release_ready(item, release)
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
