defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Two
  tabs today, one LiveView with a `live_action` per tab:

  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live); the
  primary action per row is the honest one for its state (see
  `WatchlistRow`). Refreshes on `discovery:updates` and
  `library:updates` — a completed download flips a row to In library
  without a reload.

  Friends — this install's Nostr identity (`Friends.Identity`), generated
  the first time the tab is opened, with the npub to hand out and the
  secret key behind a disclosure for export/import; below it the relay
  list, whose per-row connection state follows `friends:connections`
  live. The roster joins them with its layer.

  Subscribes to Discovery directly (it needs the full item list, not the
  `WatchlistAware` ref set — see that trait's moduledoc).

  The Feed tab arrives with the recommendations layers.
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaurWeb.Components.Discovery.WatchlistRow
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.DiscoveryLive.IdentityBlock
  alias MediaCentaurWeb.DiscoveryLive.RelayBlock

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Library.subscribe()
      Friends.subscribe()
      Friends.subscribe_connections()
    end

    {:ok,
     socket
     |> assign(:page_title, "Discovery")
     |> assign(identity_npub: nil, nsec_revealed: nil, import_armed?: false, import_draft: "")
     |> assign(relays: [], relay_status: %{})
     |> load_items()}
  end

  # The Friends tab is where the identity comes into existence — nothing
  # else in the app generates one.
  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :friends}} = socket) do
    Identity.ensure()

    {:noreply,
     socket
     |> assign(
       identity_npub: Identity.npub(),
       nsec_revealed: nil,
       import_armed?: false,
       import_draft: ""
     )
     |> assign(relay_status: Connections.status())
     |> load_relays()}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

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
        ReleaseTracking.track_from_search_async(item.title)

        {:noreply,
         put_flash(socket, :info, "Tracking #{item.title.name} — it will appear under Coming up.")}
    end
  end

  def handle_event("add_relay", %{"url" => url}, socket) do
    case Friends.add_relay(url) do
      {:ok, _relay} ->
        {:noreply, load_relays(socket)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Relay addresses start with wss:// or ws://")}
    end
  end

  def handle_event("remove_relay", %{"url" => url}, socket) do
    :ok = Friends.remove_relay(url)
    {:noreply, load_relays(socket)}
  end

  def handle_event("reveal_nsec", _params, socket),
    do: {:noreply, assign(socket, nsec_revealed: Identity.export_nsec())}

  def handle_event("hide_nsec", _params, socket), do: {:noreply, assign(socket, nsec_revealed: nil)}

  # Two-click arm (MC0027 treatment b): the first submit arms, the second
  # replaces. Costly but recoverable — the old nsec can be re-imported.
  def handle_event("import_nsec", %{"nsec" => nsec}, %{assigns: %{import_armed?: false}} = socket),
    do: {:noreply, assign(socket, import_armed?: true, import_draft: nsec)}

  def handle_event("import_nsec", %{"nsec" => nsec}, socket) do
    case Identity.import_nsec(nsec) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           identity_npub: Identity.npub(),
           nsec_revealed: nil,
           import_armed?: false,
           import_draft: ""
         )
         |> put_flash(:info, "Identity replaced")}

      {:error, :invalid_secret} ->
        {:noreply,
         socket
         |> assign(import_armed?: false, import_draft: "")
         |> put_flash(:error, "That is not a valid secret key")}
    end
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:noreply, load_items(socket)}
  end

  def handle_info({:entities_changed, %Library.Events.EntitiesChanged{}}, socket) do
    {:noreply, load_items(socket)}
  end

  # Another tab (or a later relay layer) replaced the identity. A key
  # revealed here belongs to the identity that is gone, and an arm here
  # is aimed at it too — both drop with it.
  def handle_info({:identity_changed, _event}, socket) do
    {:noreply, assign(socket, identity_npub: Identity.npub(), nsec_revealed: nil, import_armed?: false)}
  end

  def handle_info({tag, _event}, socket) when tag in [:relay_added, :relay_removed] do
    {:noreply, load_relays(socket)}
  end

  # `Connections.apply_message/2` is the owner's own fold, so the page and
  # the owner can never disagree about what a connection message means.
  def handle_info({:relay_connection, url, message}, socket) do
    entry = Map.get(socket.assigns.relay_status, url, Connections.blank_entry())
    status = Map.put(socket.assigns.relay_status, url, Connections.apply_message(entry, message))
    {:noreply, assign(socket, relay_status: status)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_items(socket) do
    items =
      Enum.map(Discovery.list_watchlist(), fn %{item: item} = row ->
        Map.put(row, :poster_url, title_poster_url(item.title))
      end)

    assign(socket, :items, items)
  end

  defp load_relays(socket), do: assign(socket, :relays, Friends.list_relays())

  # The tabs this layer hosts. Feed (`/discovery/feed`) joins here with
  # its layer.
  defp tabs(items),
    do: [
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends"}
    ]

  defp current_path(:friends), do: "/discovery/friends"
  defp current_path(_action), do: "/discovery/watchlist"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path={current_path(@live_action)}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <div class="relative" data-page-behavior="discovery" data-nav-default-zone="discovery">
        <div class="mx-auto w-full max-w-3xl space-y-4 pt-10">
          <h1 class="px-1 text-lg font-semibold">Discovery</h1>

          <.tab_strip tabs={tabs(@items)} active={@live_action} />

          <div :if={@live_action == :friends} class="space-y-4">
            <IdentityBlock.identity_block
              npub={@identity_npub}
              nsec_revealed={@nsec_revealed}
              import_armed?={@import_armed?}
              import_draft={@import_draft}
            />
            <RelayBlock.relay_block relays={@relays} status={@relay_status} />
          </div>

          <div :if={@live_action == :watchlist} class="space-y-2" data-nav-zone="grid">
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
      </div>
    </Layouts.app>
    """
  end
end
