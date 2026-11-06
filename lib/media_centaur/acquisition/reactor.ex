defmodule MediaCentaur.Acquisition.Reactor do
  @moduledoc """
  GenServer that reacts to release-tracking PubSub events.

  Subscribes to `Topics.release_tracking_updates/0`,
  `Topics.integration_availability_updates/0` and
  `Topics.watchlist_updates/0` and dispatches each domain event to
  `Acquisition.Reactor.Handlers`:

  - `{:tracking_sweep_completed}` — the refresher's sweep finished a
    want-ledger sync pass. Runs the drop planner tick
    (`Handlers.tracking_sweep_completed/0`).
  - `{:item_removed, tmdb_id, tmdb_type}` — a tracked item was removed.
    Active (`seeking`) targets for that key are cancelled.
  - `{:integration_availability_changed, :prowlarr, :up}` — Prowlarr
    recovered. Runs the drop planner tick at once
    (`Handlers.prowlarr_available/0`) so wants held through the outage
    are planned in seconds, not at the next sweep. Every other
    integration, and every down transition, falls through to the
    catch-all.
  - `{:title_intent_changed, %RungChanged{}}` — a title's rung moved.
    A raise to Grab schedules its planning (`Handlers.rung_changed/1`).

  Lives on the supervision tree as a pubsub_listener (see `Application`).
  Subscribe-and-dispatch only — all logic lives in `Handlers`.
  """

  use GenServer

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.CancelReasons
  alias MediaCentaur.Acquisition.Reactor.Handlers
  alias MediaCentaur.Topics
  alias MediaCentaur.Watchlist.Events.RungChanged

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Topics.subscribe(Topics.release_tracking_updates())
    Topics.subscribe(Topics.integration_availability_updates())
    Topics.subscribe(Topics.watchlist_updates())
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:tracking_sweep_completed}, state) do
    Handlers.tracking_sweep_completed()
    {:noreply, state}
  end

  def handle_info({:integration_availability_changed, :prowlarr, :up}, state) do
    Handlers.prowlarr_available()
    {:noreply, state}
  end

  def handle_info({:title_intent_changed, %RungChanged{} = event}, state) do
    Handlers.rung_changed(event)
    {:noreply, state}
  end

  def handle_info({:item_removed, tmdb_id, tmdb_type}, state) do
    Acquisition.cancel_active_targets_for(tmdb_id, tmdb_type, CancelReasons.item_removed())
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
