defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab:

  The feed (`/discovery`, the page's default) — what friends recommended,
  newest first. `Recommendations.list_feed/0` carries the record and the
  friend's nickname; this page joins the rest, because Recommendations
  knows nothing about the watchlist or the library:
  `Library.ExternalIds.tmdb_owners/1` and `Discovery.watchlisted_refs/0`
  decide what each row can offer.

  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live); the
  primary action per row is the honest one for its state (see
  `WatchlistRow`). A row added from the feed carries a bare
  `recommendation_id`, and this page turns it into `from <nickname>`
  (`Recommendations.get_many/1` → `Friends.list_friends/0`) — the join
  neither context may make. Refreshes on `discovery:updates` and
  `library:updates` — a completed download flips a row to In library
  without a reload.

  Friends — this install's Nostr identity (`Friends.Identity`), generated
  the first time the tab is opened, with the npub to hand out and the
  secret key behind a disclosure for export/import; below it the relay
  list, whose per-row connection state follows `friends:connections`
  live, and the roster of followed keys.

  Subscribes to Discovery directly (it needs the full item list, not the
  `WatchlistAware` ref set — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Recommendations
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaurWeb.Components.Discovery.WatchlistRow
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.Live.RecommendFlow
  alias MediaCentaurWeb.DiscoveryLive.FeedRow
  alias MediaCentaurWeb.DiscoveryLive.IdentityBlock
  alias MediaCentaurWeb.DiscoveryLive.RecommendModal
  alias MediaCentaurWeb.DiscoveryLive.RelayBlock
  alias MediaCentaurWeb.DiscoveryLive.RosterBlock

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Library.subscribe()
      Friends.subscribe()
      Friends.subscribe_connections()
      Recommendations.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Discovery")
     |> assign(identity_npub: nil, nsec_revealed: nil, import_armed?: false, import_draft: "")
     |> assign(relays: [], relay_status: %{}, friends: [])
     |> RecommendFlow.init()
     |> load_items()
     |> load_feed()}
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
     |> load_relays()
     |> load_friends()}
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

  def handle_event("watchlist_recommend", %{"tmdb-id" => tmdb_id, "media-type" => media_type}, socket)
      when media_type in ~w(movie tv_series) do
    ref = {String.to_integer(tmdb_id), String.to_existing_atom(media_type)}

    case Enum.find(socket.assigns.items, fn %{item: item} -> {item.tmdb_id, item.media_type} == ref end) do
      nil -> {:noreply, socket}
      %{item: item} -> {:noreply, RecommendFlow.open(socket, item.title)}
    end
  end

  use RecommendFlow

  def handle_event("feed_add_to_watchlist", %{"id" => id}, socket) do
    case Recommendations.get(id) do
      nil -> {:noreply, socket}
      rec -> add_recommended_to_watchlist(socket, rec)
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

  def handle_event("add_friend", %{"key" => key, "nickname" => nickname}, socket) do
    case Friends.add_friend(key, nickname) do
      {:ok, _friend} -> {:noreply, load_friends(socket)}
      {:error, :own_key} -> {:noreply, put_flash(socket, :error, "That is your own key")}
      {:error, :nickname_required} -> {:noreply, put_flash(socket, :error, "Give your friend a name")}
      {:error, _invalid} -> {:noreply, put_flash(socket, :error, "That is not a valid public key")}
    end
  end

  def handle_event("remove_friend", %{"pubkey" => pubkey}, socket) do
    :ok = Friends.remove_friend(pubkey)
    {:noreply, load_friends(socket)}
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
    {:noreply, socket |> load_items() |> load_feed()}
  end

  def handle_info({:entities_changed, %Library.Events.EntitiesChanged{}}, socket) do
    {:noreply, socket |> load_items() |> load_feed()}
  end

  def handle_info({tag, _event}, socket) when tag in [:recommendation_received, :recommendation_sent] do
    {:noreply, load_feed(socket)}
  end

  # Another tab (or a later relay layer) replaced the identity. A key
  # revealed here belongs to the identity that is gone, an arm here is
  # aimed at it too, and the pasted draft is the secret that arm would
  # have installed — all three drop with it.
  def handle_info({:identity_changed, _event}, socket) do
    {:noreply,
     assign(socket,
       identity_npub: Identity.npub(),
       nsec_revealed: nil,
       import_armed?: false,
       import_draft: ""
     )}
  end

  # Both also move the feed: its prerequisites are a relay and a friend,
  # and a roster change renames (or orphans) rows already in it.
  def handle_info({tag, _event}, socket) when tag in [:relay_added, :relay_removed] do
    {:noreply, socket |> load_relays() |> load_feed()}
  end

  def handle_info({tag, _event}, socket) when tag in [:friend_added, :friend_removed] do
    {:noreply, socket |> load_friends() |> load_feed()}
  end

  # `Connections.apply_message/2` is the owner's own fold, so the page and
  # the owner can never disagree about what a connection message means.
  def handle_info({:relay_connection, url, message}, socket) do
    entry = Map.get(socket.assigns.relay_status, url, Connections.blank_entry())
    status = Map.put(socket.assigns.relay_status, url, Connections.apply_message(entry, message))
    {:noreply, assign(socket, relay_status: status)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # The watchlist row's decoration: Discovery owns the item and library
  # presence; the poster and the provenance nickname are joined here,
  # because Discovery stores only the bare `recommendation_id` and knows
  # nothing about Recommendations or Friends.
  defp load_items(socket) do
    rows = Discovery.list_watchlist()
    nicknames = from_nicknames(rows)

    items =
      Enum.map(rows, fn %{item: item} = row ->
        Map.merge(row, %{
          poster_url: title_poster_url(item.title),
          from_nickname: Map.get(nicknames, item.recommendation_id)
        })
      end)

    assign(socket, :items, items)
  end

  # `%{recommendation_id => nickname}` for the friend-sourced rows, in one
  # recommendations query and one roster read. A recommendation or a
  # friend that is gone simply has no entry, so the row shows no marker.
  defp from_nicknames(rows) do
    ids = rows |> Enum.map(& &1.item.recommendation_id) |> Enum.reject(&is_nil/1)

    case Recommendations.get_many(ids) do
      recommendations when map_size(recommendations) == 0 ->
        %{}

      recommendations ->
        friends = Map.new(Friends.list_friends(), &{&1.pubkey, &1.nickname})

        for {id, rec} <- recommendations,
            nickname = Map.get(friends, rec.author_pubkey),
            into: %{},
            do: {id, nickname}
    end
  end

  # The feed row's decoration: Recommendations owns the record and the
  # nickname; watchlist and library presence are derived here, live, from
  # the contexts that own them.
  defp load_feed(socket) do
    rows = Recommendations.list_feed()

    owners =
      ExternalIds.tmdb_owners(Enum.map(rows, &{&1.recommendation.tmdb_id, &1.recommendation.media_type}))

    watchlisted = Discovery.watchlisted_refs()

    feed =
      Enum.map(rows, fn %{recommendation: rec} = row ->
        ref = {rec.tmdb_id, rec.media_type}

        Map.merge(row, %{
          poster_url: title_poster_url(rec.title),
          library_owner_id: Map.get(owners, ref),
          on_watchlist?: MapSet.member?(watchlisted, ref)
        })
      end)

    assign(socket,
      feed: feed,
      feed_prereqs_met?: Friends.list_relays() != [] and Friends.list_friends() != []
    )
  end

  defp add_recommended_to_watchlist(socket, rec) do
    attrs = %{source: :friend, recommendation_id: rec.id, note: rec.note}

    case Discovery.add_to_watchlist(rec.title, attrs) do
      {:ok, _item} ->
        {:noreply, load_feed(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add that to your watchlist")}
    end
  end

  defp load_relays(socket), do: assign(socket, :relays, Friends.list_relays())

  defp load_friends(socket), do: assign(socket, :friends, Friends.list_friends())

  defp tabs(feed, items),
    do: [
      %Tab{id: :feed, label: "Feed", navigate: "/discovery", count: length(feed)},
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends"}
    ]

  # Before a relay and a friend exist the feed cannot fill, so the empty
  # state names what is missing rather than implying nobody wrote.
  defp feed_empty_state(true), do: "Nothing from your friends yet."

  defp feed_empty_state(_prereqs_met),
    do: "Recommendations from your friends land here. Add a relay and a friend on the Friends tab."

  defp current_path(:friends), do: "/discovery/friends"
  defp current_path(:watchlist), do: "/discovery/watchlist"
  defp current_path(_action), do: "/discovery"

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
      <:overlays>
        <RecommendModal.recommend_modal
          subject={@recommend_subject}
          relay_counts={@recommend_relay_counts}
        />
      </:overlays>
      <div class="relative" data-page-behavior="discovery" data-nav-default-zone="discovery">
        <div class="mx-auto w-full max-w-3xl space-y-4 pt-10">
          <h1 class="px-1 text-lg font-semibold">Discovery</h1>

          <.tab_strip tabs={tabs(@feed, @items)} active={@live_action} />

          <div :if={@live_action == :feed} class="space-y-2" data-nav-zone="grid">
            <div
              :if={@feed == []}
              id="feed-empty"
              class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
            >
              {feed_empty_state(@feed_prereqs_met?)}
            </div>

            <FeedRow.feed_row :for={row <- @feed} row={row} />
          </div>

          <div :if={@live_action == :friends} class="space-y-4">
            <IdentityBlock.identity_block
              npub={@identity_npub}
              nsec_revealed={@nsec_revealed}
              import_armed?={@import_armed?}
              import_draft={@import_draft}
            />
            <RelayBlock.relay_block relays={@relays} status={@relay_status} />
            <RosterBlock.roster_block friends={@friends} />
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
              from_nickname={row.from_nickname}
              release_mode_available={@prowlarr_ready}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
