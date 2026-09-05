defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab. Every title on every
  tab is a click target opening the title detail modal
  (`TitleDetailModal`, driven by `?title=<media_type>-<id>` on the
  current tab, plus `&activity=<id>` when a person card opened it —
  refresh keeps it open, back closes it), where every verb lives:
  Download (the one-click plan, `Plans.plan_title/2` with
  `approval_policy: "automatic"`), Track release, Add to / Remove from
  watchlist, Delete (an own activity of any kind).

  The social projections (UIDR-031) come from one list: every live
  activity with its actor (`Activities.list_activities/0`), enriched
  here with what Activities cannot know — `Library.ExternalIds.tmdb_owners/1`,
  `Discovery.watchlisted_refs/0` and `Acquisition.TitleStates.for_refs/1`.

  Recommendations (`/discovery`, the page's default) — friends'
  recommendations, one row per title (`RecommendationRows`), the
  newest first. Friends (`/discovery/friends`) — one `Person` card per
  friend and one for You (`People`), each with their shelves, and the
  add-friend form below; identity and relays live on the Settings
  page's Social section, which this tab points at.

  The watchlist — title-level intent, triaged. Rows come from
  `Discovery.list_watchlist/0` (library presence derived live). A row
  added from a recommendation carries a bare `activity_id`, and this
  page turns it into `from <nickname>` (`Activities.get_many/1` →
  `Social.list_friends/0`) — the join neither context may make.

  Every row carries its acquisition state (Planning / Downloading /
  Needs review) stamped from one `TitleStates` read per load; the page
  subscribes to `acquisition:updates` so a one-click download's progress
  lands on the row without a reload, the way `library:updates` flips a
  row to In library when the file lands.

  Subscribes to Discovery directly (it needs the full item list, not the
  `WatchlistAware` ref set — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1, tmdb_cdn_url: 2]

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{PlanEvents, Plans, TitleStates}
  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Activities
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.TMDB.Client, as: TMDBClient
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.Discovery.{PersonCard, TitleDetail, TitleDetailModal, TitleRow}
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.DiscoveryLive.AddFriendBlock
  alias MediaCentaurWeb.DiscoveryLive.Logic
  alias MediaCentaurWeb.DiscoveryLive.People
  alias MediaCentaurWeb.DiscoveryLive.RecommendationRows

  require MediaCentaur.Log, as: Log
  require PursuitEvents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Discovery.subscribe()
      Library.subscribe()
      Social.subscribe()
      Activities.subscribe()
      Acquisition.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Discovery")
     |> assign(
       friends: [],
       items: [],
       activities: [],
       recommendations: [],
       people: [],
       expanded_people: MapSet.new(),
       title_detail: nil,
       scope_menu_open: false,
       today: Date.utc_today()
     )
     |> load_friends()
     |> load_items()
     |> load_activities()}
  end

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, apply_title_param(socket, params)}

  # `?title=<media_type>-<tmdb_id>` drives the modal (UIDR-017 idiom):
  # back closes, refresh keeps it, the URL is shareable. `&activity=<id>`
  # names the act a person card opened it from. An unknown ref — a
  # title on no tab — leaves it closed. A fresh open starts the live
  # TMDB preview fetch; a re-patch of the same title keeps the preview
  # it already has.
  defp apply_title_param(socket, %{"title" => param} = params) do
    activity_id = Map.get(params, "activity")

    with {:ok, ref} <- Logic.parse_title_ref(param),
         %Title{} = title <- find_title(socket, ref, activity_id) do
      case socket.assigns.title_detail do
        %TitleDetail{ref: ^ref} = open ->
          assign(socket, title_detail: build_title_detail(socket, title, open.preview, activity_id))

        _closed_or_other ->
          socket
          |> assign(
            title_detail: build_title_detail(socket, title, nil, activity_id),
            scope_menu_open: false
          )
          |> fetch_title_preview(title)
      end
    else
      _unknown -> assign(socket, title_detail: nil, scope_menu_open: false)
    end
  end

  defp apply_title_param(socket, _params), do: assign(socket, title_detail: nil, scope_menu_open: false)

  # The title lives on whichever tab knows it: the watchlist item or an activity.
  defp find_title(socket, ref, activity_id) do
    case {watch_row(socket, ref), activity_row(socket, ref, activity_id)} do
      {%{item: item}, _activity} -> item.title
      {nil, %{activity: activity}} -> activity.title
      {nil, nil} -> nil
    end
  end

  defp watch_row(socket, ref),
    do: Enum.find(socket.assigns.items, &({&1.item.tmdb_id, &1.item.media_type} == ref))

  # The activity the modal speaks for: the one named, else the title's
  # newest friend recommendation (the Recommendations row's lead), else
  # any activity for the title (a watchlist title a friend watched).
  defp activity_row(socket, ref, nil) do
    case Enum.find(socket.assigns.recommendations, &(&1.ref == ref)) do
      %{newest: newest} -> newest
      nil -> Enum.find(socket.assigns.activities, &(activity_ref(&1) == ref))
    end
  end

  defp activity_row(socket, ref, activity_id) do
    Enum.find(socket.assigns.activities, &(&1.activity.id == activity_id and activity_ref(&1) == ref))
  end

  defp activity_ref(%{activity: activity}), do: {activity.tmdb_id, activity.media_type}

  # The live preview runs as an owned async (cancelled with the view,
  # awaitable in tests); the modal reads the snapshot until it lands.
  # Without a working TMDB key the snapshot is all there is.
  defp fetch_title_preview(socket, %Title{} = title) do
    if Capabilities.tmdb_ready?() do
      ref = {title.tmdb_id, title.media_type}
      in_library? = match?({:in_library, _owner}, socket.assigns.title_detail.primary)

      start_async(socket, {:title_preview, ref}, fn -> load_title_preview(title, in_library?) end)
    else
      socket
    end
  end

  defp load_title_preview(%Title{media_type: :movie, tmdb_id: id}, in_library?) do
    with {:ok, movie} <- TMDBClient.get_movie(id), do: {:ok, TitlePreview.movie(movie, in_library?)}
  end

  defp load_title_preview(%Title{media_type: :tv_series, tmdb_id: id}, in_library?) do
    with {:ok, show} <- TMDBClient.get_tv(id), do: {:ok, TitlePreview.tv(show, in_library?)}
  end

  # The detail joins the facts the rows already carry — the rows are the
  # one representation of library, watchlist and acquisition state.
  defp build_title_detail(socket, %Title{} = title, preview, activity_id) do
    ref = {title.tmdb_id, title.media_type}
    watch_row = watch_row(socket, ref)
    activity_row = activity_row(socket, ref, activity_id)
    facts_row = watch_row || activity_row

    Logic.title_detail(title, %{
      library_owner_id: facts_row && facts_row.library_owner_id,
      on_watchlist?: watch_row != nil or (activity_row != nil and activity_row.on_watchlist?),
      acquisition_state: facts_row && facts_row.acquisition_state,
      release_mode_available: socket.assigns.prowlarr_ready,
      today: socket.assigns.today,
      poster_url: title_poster_url(title),
      backdrop_url: tmdb_cdn_url(title.backdrop_path, :w1280),
      kind: activity_row && activity_row.activity.kind,
      episode: activity_row && activity_row.activity.episode,
      sender: activity_row && !activity_row.own? && activity_row.nickname,
      note: (activity_row && activity_row.activity.note) || (watch_row && watch_row.item.note),
      acted_at: activity_row && activity_row.activity.acted_at,
      own?: activity_row && activity_row.own?,
      activity_id: activity_row && activity_row.activity.id,
      recommendations: (watch_row && watch_row.recommendations) || title_recommendations(socket, ref),
      preview: preview
    })
  end

  # A title's recommendations are its recommendation activities by this
  # identity and current friends — the rows are the one representation
  # (a former friend's carries no name, so no pennant).
  defp title_recommendations(socket, ref) do
    Enum.filter(
      socket.assigns.activities,
      &(activity_ref(&1) == ref and &1.activity.kind == :recommendation and
          (&1.own? or &1.nickname != nil))
    )
  end

  @impl true
  def handle_async({:title_preview, ref}, {:ok, {:ok, %TitlePreview{} = preview}}, socket) do
    case socket.assigns.title_detail do
      %TitleDetail{ref: ^ref} = detail ->
        {:noreply, assign(socket, :title_detail, %{detail | preview: preview})}

      _closed_or_other ->
        {:noreply, socket}
    end
  end

  def handle_async({:title_preview, _ref}, {:ok, {:error, reason}}, socket) do
    Log.debug(:tmdb, "title preview unavailable — #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async({:title_preview, _ref}, {:exit, reason}, socket) do
    Log.warning(:tmdb, "title preview crashed — #{inspect(reason)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_title", %{"ref" => ref} = params, socket) do
    query =
      case params do
        %{"activity" => activity_id} -> [title: ref, activity: activity_id]
        _title_only -> [title: ref]
      end

    {:noreply, push_patch(socket, to: discovery_path(socket, query))}
  end

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
      if detail.activity_id && !detail.own?,
        do: %{source: :friend, activity_id: detail.activity_id, note: detail.note},
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
        "title_activity_delete",
        _params,
        %{assigns: %{title_detail: %TitleDetail{activity_id: id, kind: kind}}} = socket
      )
      when is_binary(id) do
    case Activities.delete(id) do
      {:ok, _activity} ->
        {:noreply,
         socket
         |> load_activities()
         |> put_flash(:info, String.capitalize(ActivityWords.noun(kind)) <> " withdrawn")
         |> push_patch(to: discovery_path(socket))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Only your own activity can be deleted")}
    end
  end

  # A modal event with no open modal (a stale click after a close) is a no-op.
  def handle_event(event, _params, socket)
      when event in ~w(title_download title_track title_watchlist_add title_watchlist_remove title_activity_delete),
      do: {:noreply, socket}

  def handle_event("expand_person", %{"id" => id}, socket),
    do: {:noreply, update(socket, :expanded_people, &MapSet.put(&1, id))}

  def handle_event("add_friend", %{"key" => key, "nickname" => nickname}, socket) do
    case Social.add_friend(key, nickname) do
      {:ok, _friend} -> {:noreply, socket |> load_friends() |> load_activities()}
      {:error, :own_key} -> {:noreply, put_flash(socket, :error, "That is your own key")}
      {:error, :nickname_required} -> {:noreply, put_flash(socket, :error, "Give your friend a name")}
      {:error, _invalid} -> {:noreply, put_flash(socket, :error, "That is not a valid public key")}
    end
  end

  def handle_event("remove_friend", %{"pubkey" => pubkey}, socket) do
    :ok = Social.remove_friend(pubkey)
    {:noreply, socket |> load_friends() |> load_activities()}
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in [:watchlist_item_added, :watchlist_item_removed] do
    {:noreply, socket |> load_items() |> load_activities()}
  end

  def handle_info({:entities_changed, %Library.Events.EntitiesChanged{}}, socket) do
    {:noreply, socket |> load_items() |> load_activities()}
  end

  def handle_info({tag, _event}, socket)
      when tag in [:activity_received, :activity_sent, :activity_deleted] do
    {:noreply, socket |> load_items() |> load_activities()}
  end

  def handle_info({tag, _event}, socket) when tag in [:relay_added, :relay_removed] do
    {:noreply, load_activities(socket)}
  end

  def handle_info({tag, _event}, socket) when tag in [:friend_added, :friend_removed] do
    {:noreply, socket |> load_friends() |> load_activities()}
  end

  def handle_info(%PlanEvents.Changed{}, socket), do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(%struct{}, socket) when PursuitEvents.is_event(struct),
    do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # The watchlist row's decoration: Discovery owns the item and library
  # presence; the poster and the recommendations (the pennants) are
  # joined here, because Discovery knows nothing about Activities.
  defp load_items(socket) do
    rows = Discovery.list_watchlist()

    recommendations =
      Activities.recommendations_for(Enum.map(rows, &{&1.item.tmdb_id, &1.item.media_type}))

    items =
      Enum.map(rows, fn %{item: item} = row ->
        Map.merge(row, %{
          poster_url: title_poster_url(item.title),
          recommendations: Map.get(recommendations, {item.tmdb_id, item.media_type}, [])
        })
      end)

    socket
    |> assign(:items, items)
    |> stamp_acquisition_states()
  end

  # The activity row's decoration: Activities owns the record and the
  # nickname; watchlist and library presence are derived here, live,
  # from the contexts that own them. Both tabs project from this list.
  defp load_activities(socket) do
    rows = Activities.list_activities()

    owners =
      ExternalIds.tmdb_owners(Enum.map(rows, &{&1.activity.tmdb_id, &1.activity.media_type}))

    watchlisted = Discovery.watchlisted_refs()

    activities =
      Enum.map(rows, fn %{activity: activity} = row ->
        ref = {activity.tmdb_id, activity.media_type}

        Map.merge(row, %{
          poster_url: title_poster_url(activity.title),
          library_owner_id: Map.get(owners, ref),
          on_watchlist?: MapSet.member?(watchlisted, ref)
        })
      end)

    socket
    |> assign(
      activities: activities,
      recommendations_ready?: Social.list_relays() != [] and Social.list_friends() != []
    )
    |> stamp_acquisition_states()
  end

  # Acquisition state per row from one read over both lists' refs; the
  # rows are the one representation, so the projections and the open
  # detail re-read them.
  defp stamp_acquisition_states(socket) do
    refs =
      Enum.map(socket.assigns.items, &{&1.item.tmdb_id, &1.item.media_type}) ++
        Enum.map(socket.assigns.activities, &activity_ref/1)

    states = TitleStates.for_refs(Enum.uniq(refs))

    socket
    |> update(:items, fn items ->
      Enum.map(
        items,
        &Map.put(&1, :acquisition_state, Map.get(states, {&1.item.tmdb_id, &1.item.media_type}))
      )
    end)
    |> update(:activities, fn activities ->
      Enum.map(activities, &Map.put(&1, :acquisition_state, Map.get(states, activity_ref(&1))))
    end)
    |> project()
    |> refresh_title_detail()
  end

  defp project(socket) do
    now = DateTime.utc_now()

    assign(socket,
      recommendations: RecommendationRows.build(socket.assigns.activities, now: now),
      people:
        People.build(socket.assigns.activities, socket.assigns.friends,
          me: Identity.pubkey() != nil,
          now: now
        )
    )
  end

  defp refresh_title_detail(%{assigns: %{title_detail: nil}} = socket), do: socket

  defp refresh_title_detail(%{assigns: %{title_detail: detail}} = socket),
    do:
      assign(
        socket,
        :title_detail,
        build_title_detail(socket, detail.title, detail.preview, detail.activity_id)
      )

  defp load_friends(socket), do: assign(socket, :friends, Social.list_friends())

  defp tabs(recommendations, items, friends),
    do: [
      %Tab{
        id: :recommendations,
        label: "Recommendations",
        navigate: "/discovery",
        count: length(recommendations)
      },
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends", count: length(friends)}
    ]

  # Before a relay and a friend exist nothing can arrive, so the empty
  # state names what is missing rather than implying nobody wrote.
  defp recommendations_empty_state(true), do: "What your friends recommend lands here."

  defp recommendations_empty_state(_not_ready),
    do:
      "What your friends recommend lands here. Add a relay under Settings → Social and a friend on the Friends tab."

  defp current_path(:friends), do: "/discovery/friends"
  defp current_path(:watchlist), do: "/discovery/watchlist"
  defp current_path(_action), do: "/discovery"

  # Path back to the current tab; every modal open/close patch routes
  # through this so leaving the modal never dumps the user on another tab.
  defp discovery_path(socket, params \\ []) do
    base = current_path(socket.assigns.live_action)

    case URI.encode_query(params) do
      "" -> base
      query -> base <> "?" <> query
    end
  end

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
      <%!-- `title` and `activity` are modal state: stripped from the
            remembered URL so leaving the section closes the modal rather
            than reopening it on return. --%>
      <div
        class="relative"
        data-page-behavior="discovery"
        data-nav-default-zone="discovery"
        data-nav-transient-params="title activity"
      >
        <div class="mx-auto w-full max-w-3xl space-y-4 pt-10">
          <.page_header title="Discovery" class="px-1" />

          <.tab_strip tabs={tabs(@recommendations, @items, @friends)} active={@live_action} />

          <div :if={@live_action == :recommendations} class="space-y-2" data-nav-zone="grid">
            <div
              :if={@recommendations == []}
              id="recommendations-empty"
              class="glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/55"
            >
              {recommendations_empty_state(@recommendations_ready?)}
            </div>

            <TitleRow.title_row
              :for={row <- @recommendations}
              id={"recommendation-#{Logic.title_ref_param(row.ref)}"}
              title={row.title}
              poster_url={row.poster_url}
              lead={row.lead}
              markers={
                Logic.row_markers(%{
                  library_owner_id: row.library_owner_id,
                  acquisition_state: row.acquisition_state,
                  on_watchlist?: row.on_watchlist?
                })
              }
              notes={row.notes}
              recommendations={row.activities}
            />
          </div>

          <div :if={@live_action == :friends} class="space-y-4">
            <div :if={@people != []} class="space-y-3" data-nav-zone="people">
              <PersonCard.person_card
                :for={person <- @people}
                person={person}
                expanded?={MapSet.member?(@expanded_people, person.id)}
              />
            </div>
            <AddFriendBlock.add_friend_block />
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
                  on_watchlist?: false
                })
              }
              notes={Logic.note_list(row.item.note)}
              recommendations={row.recommendations}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
