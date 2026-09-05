defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab. The two title tabs are
  lists of whole-card click targets (`TitleRow`) that open the title
  detail modal (`TitleDetailModal`, driven by `?title=<media_type>-<id>`
  on the current tab — refresh keeps it open, back closes it), where
  every verb lives: Download (the one-click plan, `Plans.plan_title/2`
  with `approval_policy: "automatic"`), Track release, Add to / Remove
  from watchlist, Delete recommendation.

  Recommendations (`/discovery`, the page's default) — what friends
  recommended (**Incoming**, the default scope) or what this install
  recommended (**Yours**), newest first. `Recommendations.list_feed/0`
  carries the record and the friend's nickname; this page joins the
  rest, because Recommendations knows nothing about the watchlist, the
  library or acquisition: `Library.ExternalIds.tmdb_owners/1`,
  `Discovery.watchlisted_refs/0` and `Acquisition.TitleStates.for_refs/1`
  decide what each row shows.

  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live). A row
  added from the feed carries a bare `recommendation_id`, and this page
  turns it into `from <nickname>` (`Recommendations.get_many/1` →
  `Social.list_friends/0`) — the join neither context may make.

  Every row carries its acquisition state (Planning / Downloading /
  Needs review) stamped from one `TitleStates` read per load; the page
  subscribes to `acquisition:updates` so a one-click download's progress
  lands on the row without a reload, the way `library:updates` flips a
  row to In library when the file lands.

  Friends — the roster of followed keys, one feature of the Social
  subsystem. Identity and relays live on the Settings page's Social
  section; this tab points there.

  Subscribes to Discovery directly (it needs the full item list, not the
  `WatchlistAware` ref set — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1, tmdb_cdn_url: 2]

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{PlanEvents, Plans, TitleStates}
  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Discovery
  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Recommendations
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Social
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.{TitleDetail, TitleDetailModal, TitleRow}
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.DiscoveryLive.Logic
  alias MediaCentaurWeb.DiscoveryLive.RosterBlock

  require PursuitEvents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Library.subscribe()
      Social.subscribe()
      Recommendations.subscribe()
      Acquisition.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Discovery")
     |> assign(
       friends: [],
       feed_scope: :incoming,
       items: [],
       feed: [],
       title_detail: nil,
       scope_menu_open: false,
       today: Date.utc_today()
     )
     |> load_items()
     |> load_feed()}
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{live_action: :friends}} = socket),
    do: {:noreply, socket |> load_friends() |> apply_title_param(params)}

  def handle_params(params, _uri, socket), do: {:noreply, apply_title_param(socket, params)}

  # `?title=<media_type>-<tmdb_id>` drives the modal (UIDR-017 idiom):
  # back closes, refresh keeps it, the URL is shareable. An unknown
  # ref — a title on neither tab — leaves it closed.
  defp apply_title_param(socket, %{"title" => param}) do
    with {:ok, ref} <- Logic.parse_title_ref(param),
         %Title{} = title <- find_title(socket, ref) do
      assign(socket, title_detail: build_title_detail(socket, title), scope_menu_open: false)
    else
      _unknown -> assign(socket, title_detail: nil, scope_menu_open: false)
    end
  end

  defp apply_title_param(socket, _params), do: assign(socket, title_detail: nil, scope_menu_open: false)

  # The title lives on whichever tab knows it: the watchlist item or a feed row.
  defp find_title(socket, ref) do
    case {watch_row(socket, ref), feed_row(socket, ref)} do
      {%{item: item}, _feed} -> item.title
      {nil, %{recommendation: rec}} -> rec.title
      {nil, nil} -> nil
    end
  end

  defp watch_row(socket, ref),
    do: Enum.find(socket.assigns.items, &({&1.item.tmdb_id, &1.item.media_type} == ref))

  defp feed_row(socket, ref) do
    Enum.find(
      socket.assigns.feed,
      &({&1.recommendation.tmdb_id, &1.recommendation.media_type} == ref)
    )
  end

  # The detail joins the facts the rows already carry — the rows are the
  # one representation of library, watchlist and acquisition state.
  defp build_title_detail(socket, %Title{} = title) do
    ref = {title.tmdb_id, title.media_type}
    watch_row = watch_row(socket, ref)
    feed_row = feed_row(socket, ref)

    Logic.title_detail(title, %{
      library_owner_id:
        (watch_row && watch_row.library_owner_id) || (feed_row && feed_row.library_owner_id),
      on_watchlist?: watch_row != nil or (feed_row != nil and feed_row.on_watchlist?),
      acquisition_state:
        (watch_row && watch_row.acquisition_state) || (feed_row && feed_row.acquisition_state),
      release_mode_available: socket.assigns.prowlarr_ready,
      today: socket.assigns.today,
      poster_url: title_poster_url(title),
      backdrop_url: tmdb_cdn_url(title.backdrop_path, :w1280),
      sender: feed_row && !feed_row.own? && feed_row.nickname,
      note: (feed_row && feed_row.recommendation.note) || (watch_row && watch_row.item.note),
      recommended_at: feed_row && feed_row.recommendation.recommended_at,
      own?: feed_row && feed_row.own?,
      recommendation_id: feed_row && feed_row.recommendation.id
    })
  end

  @impl true
  def handle_event("open_title", %{"ref" => ref}, socket),
    do: {:noreply, push_patch(socket, to: discovery_path(socket, %{"title" => ref}))}

  def handle_event("close_title", _params, socket),
    do: {:noreply, push_patch(socket, to: discovery_path(socket))}

  def handle_event("title_scope_toggle", _params, socket),
    do: {:noreply, update(socket, :scope_menu_open, &(!&1))}

  def handle_event("title_scope_close", _params, socket),
    do: {:noreply, assign(socket, :scope_menu_open, false)}

  # Movies send no scope; a series sends first_season or everything.
  def handle_event(
        "title_download",
        params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ) do
    scope =
      case params do
        %{"scope" => scope} when scope in ~w(first_season everything) ->
          [scope: String.to_existing_atom(scope)]

        _movie ->
          []
      end

    :ok = Plans.plan_title(detail.title, [approval_policy: "automatic"] ++ scope)

    {:noreply,
     socket
     |> put_flash(:info, "Finding a release for #{detail.title.name}")
     |> push_patch(to: discovery_path(socket))}
  end

  def handle_event("title_track", _params, %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket) do
    ReleaseTracking.track_from_search_async(detail.title)

    {:noreply,
     socket
     |> put_flash(:info, "Tracking #{detail.title.name} — it will appear under Coming up.")
     |> push_patch(to: discovery_path(socket))}
  end

  def handle_event(
        "title_watchlist_add",
        _params,
        %{assigns: %{title_detail: %TitleDetail{} = detail}} = socket
      ) do
    attrs =
      if detail.recommendation_id && !detail.own?,
        do: %{source: :friend, recommendation_id: detail.recommendation_id, note: detail.note},
        else: %{}

    case Discovery.add_to_watchlist(detail.title, attrs) do
      {:ok, _item} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add that to your watchlist")}
    end
  end

  def handle_event(
        "title_watchlist_remove",
        _params,
        %{assigns: %{title_detail: %TitleDetail{ref: {tmdb_id, media_type}}}} = socket
      ) do
    Discovery.remove_from_watchlist(tmdb_id, media_type)
    {:noreply, push_patch(socket, to: discovery_path(socket))}
  end

  def handle_event(
        "title_recommendation_delete",
        _params,
        %{assigns: %{title_detail: %TitleDetail{recommendation_id: id}}} = socket
      )
      when is_binary(id) do
    case Recommendations.delete(id) do
      {:ok, _rec} ->
        {:noreply,
         socket
         |> load_feed()
         |> put_flash(:info, "Recommendation withdrawn")
         |> push_patch(to: discovery_path(socket))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Only your own recommendations can be deleted")}
    end
  end

  # A modal event with no open modal (a stale click after a close) is a no-op.
  def handle_event(event, _params, socket)
      when event in ~w(title_download title_track title_watchlist_add title_watchlist_remove title_recommendation_delete),
      do: {:noreply, socket}

  def handle_event("feed_scope", %{"scope" => scope}, socket) when scope in ["incoming", "own"],
    do: {:noreply, assign(socket, feed_scope: String.to_existing_atom(scope))}

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

  def handle_info(%PlanEvents.Changed{}, socket), do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(%struct{}, socket) when PursuitEvents.is_event(struct),
    do: {:noreply, stamp_acquisition_states(socket)}

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

    socket
    |> assign(:items, items)
    |> stamp_acquisition_states()
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

    socket
    |> assign(
      feed: feed,
      feed_prereqs_met?: Social.list_relays() != [] and Social.list_friends() != []
    )
    |> stamp_acquisition_states()
  end

  # Acquisition state per row from one read over both tabs' refs; the
  # rows are the one representation, and the open detail re-reads them.
  defp stamp_acquisition_states(socket) do
    refs =
      Enum.map(socket.assigns.items, &{&1.item.tmdb_id, &1.item.media_type}) ++
        Enum.map(socket.assigns.feed, &{&1.recommendation.tmdb_id, &1.recommendation.media_type})

    states = TitleStates.for_refs(Enum.uniq(refs))

    socket
    |> update(:items, fn items ->
      Enum.map(
        items,
        &Map.put(&1, :acquisition_state, Map.get(states, {&1.item.tmdb_id, &1.item.media_type}))
      )
    end)
    |> update(:feed, fn feed ->
      Enum.map(
        feed,
        &Map.put(
          &1,
          :acquisition_state,
          Map.get(states, {&1.recommendation.tmdb_id, &1.recommendation.media_type})
        )
      )
    end)
    |> refresh_title_detail()
  end

  defp refresh_title_detail(%{assigns: %{title_detail: nil}} = socket), do: socket

  defp refresh_title_detail(%{assigns: %{title_detail: detail}} = socket),
    do: assign(socket, :title_detail, build_title_detail(socket, detail.title))

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

  # Path back to the current tab; every modal open/close patch routes
  # through this so leaving the modal never dumps the user on another tab.
  defp discovery_path(socket, params \\ %{}) do
    base = current_path(socket.assigns.live_action)

    case URI.encode_query(params) do
      "" -> base
      query -> base <> "?" <> query
    end
  end

  defp feed_lead(%{own?: true, recommendation: rec}),
    do: "You · #{Format.relative_ago(rec.recommended_at)}"

  defp feed_lead(%{nickname: nickname, recommendation: rec}),
    do: "from #{nickname} · #{Format.relative_ago(rec.recommended_at)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path={current_path(@live_action)}
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <TitleDetailModal.title_detail_modal
          detail={@title_detail}
          scope_menu_open={@scope_menu_open}
        />
      </:overlays>
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

              <TitleRow.title_row
                :for={row <- scoped_feed(@feed, @feed_scope)}
                id={"feed-#{row.recommendation.id}"}
                title={row.recommendation.title}
                poster_url={row.poster_url}
                lead={feed_lead(row)}
                markers={
                  Logic.row_markers(%{
                    library_owner_id: row.library_owner_id,
                    acquisition_state: row.acquisition_state,
                    from_nickname: nil,
                    on_watchlist?: row.on_watchlist?
                  })
                }
                secondary={row.recommendation.note}
              />
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

            <%!-- A watchlist row never says On watchlist about itself —
                  that is the tab's own fact. --%>
            <TitleRow.title_row
              :for={row <- @items}
              id={"watchlist-item-#{row.item.media_type}-#{row.item.tmdb_id}"}
              title={row.item.title}
              poster_url={row.poster_url}
              markers={
                Logic.row_markers(%{
                  library_owner_id: row.library_owner_id,
                  acquisition_state: row.acquisition_state,
                  from_nickname: row.from_nickname,
                  on_watchlist?: false
                })
              }
              secondary={row.item.note}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
