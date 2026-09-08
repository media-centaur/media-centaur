defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab. Every title on every
  tab is a click target opening the title detail modal
  (`TitleDetailModal`, hosted through `TitleDetailHost` and driven by
  `?title=<media_type>-<id>` on the current tab, plus `&activity=<id>`
  when a person card opened it — refresh keeps it open, back closes it),
  where the verbs live: Download (the one-click plan), Add to / Remove
  from watchlist, Delete (an own activity of any kind), and the
  tracking-mode control.

  The social projections (UIDR-031) come from one list: every live
  activity with its actor (`Activities.list_activities/0`), enriched
  here with what Activities cannot know — `Library.ExternalIds.tmdb_owners/1`,
  `Discovery.rungs/0` and `Acquisition.TitleStates.for_refs/1`.

  Recommendations (`/discovery`, the page's default) — friends'
  recommendations, one row per title (`RecommendationRows`), the
  newest first. Friends (`/discovery/friends`) — one `Person` card per
  friend and one for You (`People`), each with their shelves, and the
  add-friend form below; identity and relays live on the Settings
  page's Social section, which this tab points at.

  The watchlist — authored intent, and the arming surface (UIDR-035).
  Rows come from `Discovery.list_watchlist/0` (library presence derived
  live), each showing its tracking mode and, when it has one, its next
  release date as quiet markers — joined here from `ReleaseTracking`,
  because Discovery stays free of tracking (ADR-065); a row is armed
  from its modal. A row added from a
  recommendation carries a bare `activity_id`, and this page turns it
  into `from <nickname>` (`Activities.get_many/1` →
  `Social.list_friends/0`) — the join neither context may make.

  Every row carries its acquisition state (Planning / Downloading /
  Needs review) stamped from one `TitleStates` read per load; the page
  subscribes to `acquisition:updates` so a one-click download's progress
  lands on the row without a reload, the way `library:updates` flips a
  row to In library when the file lands.

  Subscribes to Discovery directly (it needs the full item list, not the
  `IntentAware` rung map — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{AutoGrabSettings, PlanEvents, TitleStates}
  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Activities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaurWeb.Components.Discovery.{PersonCard, TitleDetailModal, TitleRow}
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.DiscoveryLive.AddFriendBlock
  alias MediaCentaurWeb.DiscoveryLive.Logic
  alias MediaCentaurWeb.DiscoveryLive.People
  alias MediaCentaurWeb.DiscoveryLive.RecommendationRows
  alias MediaCentaurWeb.Live.TitleDetailHost
  alias MediaCentaurWeb.TitleRef

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
       default_grab_mode: AutoGrabSettings.load().default_mode,
       today: Date.utc_today()
     )
     |> load_friends()
     |> load_items()
     |> load_activities()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # --- TitleDetailHost ---

  # The title lives on whichever tab knows it: the watchlist item or an
  # activity. The host's facts are the feed provenance and the pennants;
  # the trait reads everything else from the contexts.
  @impl TitleDetailHost
  def resolve_title(socket, ref, params) do
    activity_id = Map.get(params, "activity")
    watch_row = watch_row(socket, ref)
    activity_row = activity_row(socket, ref, activity_id)

    case {watch_row, activity_row} do
      {nil, nil} ->
        nil

      _known ->
        title = if watch_row, do: watch_row.item.title, else: activity_row.activity.title

        {title,
         %{
           kind: activity_row && activity_row.activity.kind,
           sender: activity_row && !activity_row.own? && activity_row.nickname,
           note: (activity_row && activity_row.activity.note) || (watch_row && watch_row.item.note),
           own?: activity_row && activity_row.own?,
           activity_id: activity_row && activity_row.activity.id,
           friend_activity:
             (watch_row && watch_row.friend_activity) || title_friend_activity(socket, ref)
         }}
    end
  end

  @impl TitleDetailHost
  def title_detail_path(socket, query), do: discovery_path(socket, query)

  defp watch_row(socket, ref),
    do: Enum.find(socket.assigns.items, &({&1.item.tmdb_id, &1.item.media_type} == ref))

  # The activity the modal speaks for: the one named, else the title's
  # newest friend recommendation (the Recommendations row's lead), else
  # any friend's activity for the title. Never an own act unless named —
  # the You card names it; a watchlist title is not a place to narrate
  # your own broadcasts back to you.
  defp activity_row(socket, ref, nil) do
    case Enum.find(socket.assigns.recommendations, &(&1.ref == ref)) do
      %{newest: newest} ->
        newest

      nil ->
        Enum.find(socket.assigns.activities, &(activity_ref(&1) == ref and not &1.own?))
    end
  end

  defp activity_row(socket, ref, activity_id) do
    Enum.find(socket.assigns.activities, &(&1.activity.id == activity_id and activity_ref(&1) == ref))
  end

  defp activity_ref(%{activity: activity}), do: {activity.tmdb_id, activity.media_type}

  # A title's friend activity, for a title the watchlist does not carry:
  # every act on it by a current friend, plus own recommendations — the
  # feed rows are the one representation (a former friend's carries no
  # name, so no pennant).
  defp title_friend_activity(socket, ref) do
    Enum.filter(
      socket.assigns.activities,
      &(activity_ref(&1) == ref and
          ((&1.own? and &1.activity.kind == :recommendation) or &1.nickname != nil))
    )
  end

  @impl true
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
  def handle_info({:title_intent_changed, _event}, socket) do
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

  # A mode moved, an arm landed, a calendar refreshed: the rows' mode and
  # next date come from the tracked titles.
  def handle_info({:releases_updated, _item_ids}, socket), do: {:noreply, load_items(socket)}

  def handle_info(%PlanEvents.Changed{}, socket), do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(%struct{}, socket) when PursuitEvents.is_event(struct),
    do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # The list row's decoration: Discovery owns the record and library
  # presence; the poster, the friend activity (the pennants) and the
  # tracked title's next date are joined here, because Discovery knows
  # nothing about Activities or ReleaseTracking. The rung comes straight
  # off the record — it is the authored fact, not something to look up.
  defp load_items(socket) do
    rows = Discovery.list_intents()

    friend_activity =
      Activities.friend_activity_for(Enum.map(rows, &{&1.intent.tmdb_id, &1.intent.media_type}))

    tracked = Map.new(ReleaseTracking.list_all_items(), &{{&1.tmdb_id, &1.media_type}, &1})

    items =
      Enum.map(rows, fn %{intent: intent} = row ->
        tracked_item = Map.get(tracked, {intent.tmdb_id, intent.media_type})

        row
        |> Map.put(:item, intent)
        |> Map.merge(%{
          poster_url: title_poster_url(intent.title),
          friend_activity: Map.get(friend_activity, {intent.tmdb_id, intent.media_type}, []),
          rung: intent.rung,
          next_air_date: next_air_date(tracked_item, socket.assigns.today)
        })
      end)

    socket
    |> assign(:items, items)
    |> stamp_acquisition_states()
  end

  # No tracked title, no next date — the rung below Follow keeps no calendar.
  defp next_air_date(nil, _today), do: nil
  defp next_air_date(item, today), do: Logic.next_air_date(item.releases, today)

  # The activity row's decoration: Activities owns the record and the
  # nickname; watchlist and library presence are derived here, live,
  # from the contexts that own them. Both tabs project from this list.
  defp load_activities(socket) do
    rows = Activities.list_activities()

    owners =
      ExternalIds.tmdb_owners(Enum.map(rows, &{&1.activity.tmdb_id, &1.activity.media_type}))

    rungs = Discovery.rungs()

    activities =
      Enum.map(rows, fn %{activity: activity} = row ->
        ref = {activity.tmdb_id, activity.media_type}

        Map.merge(row, %{
          poster_url: title_poster_url(activity.title),
          library_owner_id: Map.get(owners, ref),
          rung: Map.get(rungs, ref)
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
    |> TitleDetailHost.refresh_title_detail()
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

  # Before a relay and a friend exist nothing can arrive, so the empty state
  # names what is missing rather than implying nobody wrote. The two cases
  # differ in what the reader can do next, which is why they are separate copy
  # and why only one of them carries actions.
  defp recommendations_empty_state(true), do: "Titles your friends recommend land here, newest first."

  defp recommendations_empty_state(_not_ready),
    do:
      "Media Centaur reaches your friends over a relay. Add one, then add a friend by the public key they give you."

  defp current_path(:friends), do: "/discovery/friends"
  defp current_path(:watchlist), do: "/discovery/watchlist"
  defp current_path(_action), do: "/discovery"

  # Path back to the current tab; every modal open/close patch routes
  # through this so leaving the modal never dumps the user on another tab.
  defp discovery_path(socket, params) do
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
          today={@today}
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
            <.empty_state
              :if={@recommendations == []}
              id="recommendations-empty"
              icon="hero-users"
              headline="Recommendations from friends land here"
            >
              {recommendations_empty_state(@recommendations_ready?)}
              <:action :if={not @recommendations_ready?}>
                <.button
                  variant="primary"
                  size="sm"
                  navigate={~p"/settings?section=social"}
                  data-nav-item
                  tabindex="0"
                >
                  Add a relay
                </.button>
              </:action>
              <:action :if={not @recommendations_ready?}>
                <.button
                  variant="dismiss"
                  size="sm"
                  navigate={~p"/discovery/friends"}
                  data-nav-item
                  tabindex="0"
                >
                  Add a friend
                </.button>
              </:action>
            </.empty_state>

            <TitleRow.title_row
              :for={row <- @recommendations}
              id={"recommendation-#{TitleRef.param(row.ref)}"}
              title={row.title}
              poster_url={row.poster_url}
              lead={row.lead}
              markers={
                Logic.row_markers(%{
                  library_owner_id: row.library_owner_id,
                  acquisition_state: row.acquisition_state,
                  rung: row.rung
                })
              }
              notes={row.notes}
              friend_activity={row.activities}
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
            <.empty_state
              :if={@items == []}
              id="watchlist-empty"
              icon="hero-bookmark"
              headline="Titles you save land here"
            >
              Bookmark a title from a search or its detail view and it is kept here until you
              watch it.
              <:action>
                <.button
                  variant="primary"
                  size="sm"
                  navigate={~p"/incoming"}
                  data-nav-item
                  tabindex="0"
                >
                  Search for a title
                </.button>
              </:action>
            </.empty_state>

            <%!-- A watchlist row never says On watchlist about itself —
                  that is the tab's own fact. Its mode is shown, never set
                  here: the row's modal is where you arm (UIDR-035). --%>
            <TitleRow.title_row
              :for={row <- @items}
              id={"watchlist-item-#{row.item.media_type}-#{row.item.tmdb_id}"}
              title={row.item.title}
              poster_url={row.poster_url}
              markers={
                Logic.row_markers(%{
                  library_owner_id: row.library_owner_id,
                  acquisition_state: row.acquisition_state,
                  rung: row.rung,
                  default_grab_mode: @default_grab_mode,
                  next_air_date: row.next_air_date,
                  today: @today
                })
              }
              notes={Logic.note_list(row.item.note)}
              friend_activity={row.friend_activity}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
