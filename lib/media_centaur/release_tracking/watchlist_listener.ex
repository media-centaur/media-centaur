defmodule MediaCentaur.ReleaseTracking.WatchlistListener do
  @moduledoc """
  Reacts to watchlist change broadcasts on behalf of release tracking,
  mirroring `LibraryListener` for the other tracking reason ([ADR-065]).

  - `{:watchlist_item_removed, %{tmdb_id:, media_type:}}` →
    `ReleaseTracking.reconcile/2`

  Only removal is interesting. Adding a title to the watchlist creates no
  tracked title — arming is a second, deliberate act, and it goes through
  `Discovery.arm/2` rather than through this listener. Removal is the
  event that can *drop* a reason, and dropping is the only direction a
  listener is ever allowed to move a title: nothing but a person may arm.

  Dependency direction matches `LibraryListener` — release tracking
  consumes Discovery, never the reverse.

  Skipped in `:test`; tests call `ReleaseTracking.reconcile/2` directly.

  [ADR-065]: `decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md`
  """
  use GenServer

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Topics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Topics.subscribe(Topics.discovery_updates())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:watchlist_item_removed, %{tmdb_id: tmdb_id, media_type: media_type}}, state) do
    ReleaseTracking.reconcile(tmdb_id, media_type)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
