defmodule MediaCentaurWeb.WatchlistLive do
  @moduledoc """
  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live); the
  primary action per row is the honest one for its state (see
  `WatchlistRow`). Refreshes on `discovery:updates` and
  `library:updates` — a completed download flips a row to In library
  without a reload.

  Subscribes to Discovery directly (it needs the full item list, not the
  `WatchlistAware` ref set — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.LiveHelpers, only: [tmdb_cdn_url: 2]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaurWeb.Components.Discovery.WatchlistRow

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Library.subscribe()
    end

    {:ok, socket |> assign(:page_title, "Watchlist") |> load_items()}
  end

  @impl true
  def handle_event("watchlist_remove", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    Discovery.remove_from_watchlist(String.to_integer(tmdb_id), String.to_existing_atom(media_type))
    {:noreply, socket}
  end

  def handle_event("watchlist_track", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    ref = {String.to_integer(tmdb_id), String.to_existing_atom(media_type)}

    case Enum.find(socket.assigns.items, fn %{item: item} -> {item.tmdb_id, item.media_type} == ref end) do
      nil ->
        {:noreply, socket}

      %{item: item} ->
        ReleaseTracking.track_from_search_async(%{
          tmdb_id: item.tmdb_id,
          media_type: item.media_type,
          name: item.name,
          poster_path: item.poster_path
        })

        {:noreply, put_flash(socket, :info, "Tracking #{item.name} — it will appear under Coming up.")}
    end
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:noreply, load_items(socket)}
  end

  def handle_info({:entities_changed, %Library.Events.EntitiesChanged{}}, socket) do
    {:noreply, load_items(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_items(socket) do
    items =
      Enum.map(Discovery.list_watchlist(), fn %{item: item} = row ->
        Map.put(row, :poster_url, poster_url(item))
      end)

    assign(socket, :items, items)
  end

  # Referenced-tier artwork once the add-time ensure has landed; TMDB
  # hotlink as the browsing-tier fallback (same ladder as search rows).
  defp poster_url(item) do
    TmdbArtwork.urls(item.media_type, item.tmdb_id).poster_url ||
      tmdb_cdn_url(item.poster_path, :w92)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_watchlist={@show_watchlist}
      flash={@flash}
      current_path="/watchlist"
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <div class="relative" data-page-behavior="watchlist" data-nav-default-zone="watchlist">
        <div class="mx-auto w-full max-w-3xl space-y-2 pt-10" data-nav-zone="grid">
          <h1 class="px-1 text-lg font-semibold">Watchlist</h1>

          <div
            :if={@items == []}
            id="watchlist-empty"
            class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
          >
            Nothing on your watchlist yet. Titles you save from a search land here.
          </div>

          <WatchlistRow.watchlist_row
            :for={row <- @items}
            item={row.item}
            library_owner_id={row.library_owner_id}
            poster_url={row.poster_url}
            release_mode_available={@prowlarr_ready}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
