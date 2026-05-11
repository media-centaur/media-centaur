defmodule MediaCentarr.Acquisition.Reactor do
  @moduledoc """
  GenServer that reacts to release-tracking PubSub events.

  Subscribes to `Topics.release_tracking_updates/0` and translates each
  domain event into a corresponding `Acquisition` operation:

  - `{:release_ready, item, release}` — a tracked release is now available.
    Routed through `Acquisition.handle_release_ready_event/2`, which
    asks `AutoGrabPolicy.decide/3` whether to enqueue, skip, or cancel.
    The capability gate is enforced inside the policy — when Prowlarr
    is not configured, the message is dropped.
  - `{:item_removed, tmdb_id, tmdb_type}` — a tracked item was removed.
    Active (`seeking`) targets for that key are cancelled.

  Lives on the supervision tree as a pubsub_listener (see `Application`).
  Contains no domain logic of its own — all work lives in `Acquisition`.
  """

  use GenServer

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.CancelReasons
  alias MediaCentarr.Topics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.release_tracking_updates())
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:release_ready, item, release}, state) do
    Acquisition.handle_release_ready_event(item, release)
    {:noreply, state}
  end

  def handle_info({:item_removed, tmdb_id, tmdb_type}, state) do
    Acquisition.cancel_active_targets_for(tmdb_id, tmdb_type, CancelReasons.item_removed())
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
