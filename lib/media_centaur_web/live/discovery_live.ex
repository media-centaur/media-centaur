defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab:

  Recommendations (`/discovery`, the page's default) — what friends
  recommended (**Incoming**, the default scope) or what this install
  recommended (**Yours**, where each row can be deleted, which withdraws
  it from every relay), newest first. `Recommendations.list_feed/0`
  carries the record and the friend's nickname; this page joins the
  rest, because Recommendations knows nothing about the watchlist or the
  library: `Library.ExternalIds.tmdb_owners/1` and
  `Discovery.watchlisted_refs/0` decide what each row can offer.
  Recommending itself happens on a title's detail page.

  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live); the
  primary action per row is the honest one for its state (see
  `WatchlistRow`). A row added from the feed carries a bare
  `recommendation_id`, and this page turns it into `from <nickname>`
  (`Recommendations.get_many/1` → `Social.list_friends/0`) — the join
  neither context may make. Refreshes on `discovery:updates` and
  `library:updates` — a completed download flips a row to In library
  without a reload.

  Friends — the roster of followed keys, one feature of the Social
  subsystem. Identity and relays live on the Settings page's Social
  section; this tab points there.

  Subscribes to Discovery directly (it needs the full item list, not the
  `WatchlistAware` ref set — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Social
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Recommendations
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaurWeb.Components.Discovery.WatchlistRow
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.DiscoveryLive.FeedRow
  alias MediaCentaurWeb.DiscoveryLive.RosterBlock

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Library.subscribe()
      Social.subscribe()
      Recommendations.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Discovery")
     |> assign(friends: [], feed_scope: :incoming)
     |> load_items()
     |> load_feed()}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :friends}} = socket),
    do: {:noreply, load_friends(socket)}

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

  def handle_event("feed_scope", %{"scope" => scope}, socket) when scope in ["incoming", "own"],
    do: {:noreply, assign(socket, feed_scope: String.to_existing_atom(scope))}

  def handle_event("feed_delete", %{"id" => id}, socket) do
    case Recommendations.delete(id) do
      {:ok, _rec} ->
        {:noreply, socket |> load_feed() |> put_flash(:info, "Recommendation withdrawn")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Only your own recommendations can be deleted")}
    end
  end

  def handle_event("feed_add_to_watchlist", %{"id" => id}, socket) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Recommendations.Recommendation{} = rec <- Recommendations.get(id) do
      add_recommended_to_watchlist(socket, rec)
    else
      _not_found_or_invalid -> {:noreply, socket}
    end
  end

  def handle_event("add_friend", %{"key" => key, "nickname" => nickname}, socket) do
    case Social.add_friend(key, nickname) do
      {:ok, _friend} -> {:noreply, load_friends(socket)}
      {:error, :own_key} -> {:noreply, put_flash(socket, :error, "That is your own key")}
      {:error, :nickname_required} -> {:noreply, put_flash(socket, :error, "Give your friend a name")}
      {:error, _invalid} -> {:noreply, put_flash(socket, :error, "That is not a valid public key")}
    end
  end

  def handle_event("remove_friend", %{"pubkey" => pubkey}, socket) do
    :ok = Social.remove_friend(pubkey)
    {:noreply, load_friends(socket)}
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:noreply, socket |> load_items() |> load_feed()}
  end

  def handle_info({:entities_changed, %Library.Events.EntitiesChanged{}}, socket) do
    {:noreply, socket |> load_items() |> load_feed()}
  end

  def handle_info({tag, _event}, socket)
      when tag in [:recommendation_received, :recommendation_sent, :recommendation_deleted] do
    {:noreply, load_feed(socket)}
  end

  def handle_info({tag, _event}, socket) when tag in [:relay_added, :relay_removed] do
    {:noreply, load_feed(socket)}
  end

  def handle_info({tag, _event}, socket) when tag in [:friend_added, :friend_removed] do
    {:noreply, socket |> load_friends() |> load_feed()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # The watchlist row's decoration: Discovery owns the item and library
  # presence; the poster and the provenance nickname are joined here,
  # because Discovery stores only the bare `recommendation_id` and knows
  # nothing about Recommendations or Social.
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
        friends = Map.new(Social.list_friends(), &{&1.pubkey, &1.nickname})

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
      feed_prereqs_met?: Social.list_relays() != [] and Social.list_friends() != []
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

  defp load_friends(socket), do: assign(socket, :friends, Social.list_friends())

  @doc "The feed rows in one scope: `:incoming` (friends') or `:own` (this install's)."
  @spec scoped_feed([map()], :incoming | :own) :: [map()]
  def scoped_feed(feed, :incoming), do: Enum.reject(feed, & &1.own?)
  def scoped_feed(feed, :own), do: Enum.filter(feed, & &1.own?)

  @doc "How many feed rows fall in a scope."
  @spec scope_count([map()], :incoming | :own) :: non_neg_integer()
  def scope_count(feed, scope), do: feed |> scoped_feed(scope) |> length()

  defp tabs(feed, items),
    do: [
      %Tab{
        id: :recommendations,
        label: "Recommendations",
        navigate: "/discovery",
        count: scope_count(feed, :incoming)
      },
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends"}
    ]

  # Before a relay and a friend exist the feed cannot fill, so the empty
  # state names what is missing rather than implying nobody wrote.
  defp feed_empty_state(:own, _prereqs_met),
    do: "Titles you recommend from their detail page show up here."

  defp feed_empty_state(:incoming, true), do: "Nothing from your friends yet."

  defp feed_empty_state(:incoming, _prereqs_met),
    do:
      "Recommendations from your friends land here. Add a relay under Settings → Social and a friend on the Friends tab."

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
      <:overlays></:overlays>
      <div class="relative" data-page-behavior="discovery" data-nav-default-zone="discovery">
        <div class="mx-auto w-full max-w-3xl space-y-4 pt-10">
          <.page_header title="Discovery" class="px-1" />

          <.tab_strip tabs={tabs(@feed, @items)} active={@live_action} />

          <div :if={@live_action == :recommendations} class="space-y-3">
            <%!-- Iteration-phase control (spec decision 11): no input-system
                  zone yet; the hardening pass gives it one. --%>
            <div class="flex gap-1 px-1">
              <button
                :for={{scope, label} <- [incoming: "Incoming", own: "Yours"]}
                type="button"
                id={"feed-scope-#{scope}"}
                class={["zone-tab cursor-pointer", @feed_scope == scope && "zone-tab-active"]}
                phx-click="feed_scope"
                phx-value-scope={scope}
              >
                {label}
                <.badge :if={scope_count(@feed, scope) > 0} variant="ghost" class="ml-1">
                  {scope_count(@feed, scope)}
                </.badge>
              </button>
            </div>

            <div class="space-y-2" data-nav-zone="grid">
              <div
                :if={scoped_feed(@feed, @feed_scope) == []}
                id="feed-empty"
                class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
              >
                {feed_empty_state(@feed_scope, @feed_prereqs_met?)}
              </div>

              <FeedRow.feed_row :for={row <- scoped_feed(@feed, @feed_scope)} row={row} />
            </div>
          </div>

          <div :if={@live_action == :friends} class="space-y-4">
            <RosterBlock.roster_block friends={@friends} />
            <p id="friends-settings-pointer" class="px-1 text-xs text-base-content/55">
              Your identity and relays are under <.link
                navigate={~p"/settings?section=social"}
                class="link link-primary"
              >
                Settings → Social
              </.link>.
            </p>
          </div>

          <div :if={@live_action == :watchlist} class="space-y-2" data-nav-zone="grid">
            <div
              :if={@items == []}
              id="watchlist-empty"
              class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
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
