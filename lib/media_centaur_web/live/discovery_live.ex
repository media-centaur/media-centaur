defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab. Every title on every
  tab is a click target opening the title detail modal
  (`TitleDetailModal`, hosted through `TitleDetailHost` and driven by
  `?title=<media_type>-<id>` on the current tab, plus `&activity=<id>`
  when an entry or a person card opened it — refresh keeps it open, back
  closes it), where the verbs live: Download (the one-click plan), the
  ladder, Delete (an own activity of any kind), and the tracking-mode
  control.

  The social projections come from one list: every live activity with
  its actor (`Activities.list_activities/0`), enriched here with what
  Activities cannot know — `Library.ExternalIds.tmdb_owners/1`,
  `Discovery.rungs/0` and `Acquisition.TitleStates.for_refs/1`.

  Feed (`/discovery`, the page's default; UIDR-038) — friends'
  recommendations and listings, one entry per action, newest first,
  flat (`FeedEntries`), the newest `feed_window` of them and a *Show
  older* control past that (`feed_show_older`). An entry's toolbar
  holds the three verbs that live outside the modal: `feed_list` (the
  bottom rung as a toggle — List, Listed, or Following as plain state),
  `feed_download` (the one-click plan, the modal's plain Download) and
  `ignore_title` (the Ignored rung, with the Undo toast). Friends
  (`/discovery/friends`) — one `Person` card per friend and one for You
  (`People`), each with their shelves, and the add-friend form below;
  identity and relays live on the Settings page's Social section, which
  this tab points at.

  The watchlist — authored intent, and the arming surface (UIDR-035).
  Rows come from `Discovery.list_watchlist/0` (library presence derived
  live), each showing its tracking mode and, when it has one, its next
  release date as quiet markers — joined here from `ReleaseTracking`,
  because Discovery stays free of tracking (ADR-065); a row is armed
  from its modal. A row added from a friend's action carries a bare
  `activity_id`, and this page turns it into `from <nickname>`
  (`Activities.get_many/1` → `Social.list_friends/0`) — the join neither
  context may make.

  A listing or an ignore made from an entry carries that entry's
  activity as provenance (`TitleIntent.friend_provenance/2`), the way
  the modal's ladder does. Because Ignore shows no state to reverse, it
  gets an undo toast (`ignore_undo` restores the rung the title had;
  `ignore_undo_dismiss` clears the toast, by click or by expiry). The
  ladder's own Ignore has no toast: the ladder is its own undo.

  Every row and entry carries its acquisition state (Planning /
  Downloading / Needs review) stamped from one `TitleStates` read per
  load; the page subscribes to `acquisition:updates` so a one-click
  download's progress lands without a reload, the way `library:updates`
  flips a title to In library when the file lands.

  Subscribes to Discovery directly (it needs the full item list, not the
  `IntentAware` rung map — see that trait's moduledoc).
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{AutoGrabSettings, PlanEvents, Plans, TitleStates}
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Activities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Library.Posters
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaurWeb.Components.ActionToast
  alias MediaCentaurWeb.Components.Discovery.FeedEntryCard
  alias MediaCentaurWeb.Components.Discovery.PersonCard
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.Title.DetailModal, as: TitleDetailModal
  alias MediaCentaurWeb.Components.Title.Row, as: TitleRow
  alias MediaCentaurWeb.DiscoveryLive.ActivityPosters
  alias MediaCentaurWeb.DiscoveryLive.AddFriendBlock
  alias MediaCentaurWeb.DiscoveryLive.FeedEntries
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Live.RecommendModal
  alias MediaCentaurWeb.DiscoveryLive.People
  alias MediaCentaurWeb.Live.TitleDetailHost

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
       feed: [],
       feed_has_older?: false,
       feed_window: FeedEntries.page_size(),
       people: [],
       expanded_people: MapSet.new(),
       ignore_undo: nil,
       warmed_artwork: MapSet.new(),
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
  # newest friend recommendation (it carries the note), else any friend's
  # activity for the title. Never an own act unless named — the You card
  # names it; a watchlist title is not a place to narrate your own
  # broadcasts back to you.
  defp activity_row(socket, ref, nil) do
    friends = Enum.filter(socket.assigns.activities, &(activity_ref(&1) == ref and not &1.own?))
    Enum.find(friends, &(&1.activity.kind == :recommendation)) || List.first(friends)
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

  # --- the Feed's toolbar — see the moduledoc ---

  def handle_event("feed_show_older", _params, socket) do
    {:noreply, socket |> update(:feed_window, &(&1 + FeedEntries.page_size())) |> project()}
  end

  # The bottom rung as a toggle. Following is plain state: the ladder is
  # in the modal for that.
  def handle_event("feed_list", %{"activity" => id}, socket) do
    case feed_entry(socket, id) do
      %FeedEntry{list_slot: :list} = entry ->
        {:ok, _intent} = ReleaseTracking.set_rung(entry.title, :list, entry_provenance(entry))
        {:noreply, socket}

      %FeedEntry{list_slot: :listed} = entry ->
        {:ok, nil} = ReleaseTracking.set_rung(entry.title, :off)
        {:noreply, socket}

      _following_or_unknown ->
        {:noreply, socket}
    end
  end

  # The modal's plain Download: no scope, so the planner's default.
  def handle_event("feed_download", %{"activity" => id}, socket) do
    case feed_entry(socket, id) do
      %FeedEntry{download_slot: :download} = entry ->
        :ok = Plans.plan_title(entry.title, approval_policy: "automatic")
        {:noreply, put_flash(socket, :info, TitleDetailHost.download_flash(entry.title.name, false))}

      _state_or_unknown ->
        {:noreply, socket}
    end
  end

  # The rung the title had is kept for Undo; nil is Off, which
  # set_rung/2 spells as such.
  def handle_event("ignore_title", %{"activity" => id}, socket) do
    case feed_entry(socket, id) do
      %FeedEntry{} = entry ->
        {:ok, _intent} = ReleaseTracking.set_rung(entry.title, :ignored, entry_provenance(entry))

        {:noreply,
         assign(socket, :ignore_undo, %{title: entry.title, previous_rung: entry.rung || :off})}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("ignore_undo", _params, %{assigns: %{ignore_undo: %{} = undo}} = socket) do
    {:ok, _intent} = ReleaseTracking.set_rung(undo.title, undo.previous_rung)
    {:noreply, assign(socket, :ignore_undo, nil)}
  end

  def handle_event("ignore_undo", _params, socket), do: {:noreply, socket}

  def handle_event("ignore_undo_dismiss", _params, socket),
    do: {:noreply, assign(socket, :ignore_undo, nil)}

  defp feed_entry(socket, id), do: Enum.find(socket.assigns.feed, &(&1.activity_id == id))

  defp entry_provenance(%FeedEntry{activity_id: id, note: note}),
    do: TitleIntent.friend_provenance(id, note)

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
    rows = Discovery.list_watchlist()

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
  # The poster too — an activity snapshot carries no poster path, so
  # only this page knows which artwork tier the title lives in
  # (`ActivityPosters`).
  defp load_activities(socket) do
    rows = Activities.list_activities()

    owners =
      ExternalIds.tmdb_owners(Enum.map(rows, &{&1.activity.tmdb_id, &1.activity.media_type}))

    library_posters = owners |> ActivityPosters.library_refs() |> Posters.urls_by_refs()
    rungs = Discovery.rungs()

    activities =
      Enum.map(rows, fn %{activity: activity} = row ->
        ref = {activity.tmdb_id, activity.media_type}

        Map.merge(row, %{
          poster_url: ActivityPosters.url(activity, owners, library_posters),
          library_owner_id: Map.get(owners, ref),
          rung: Map.get(rungs, ref)
        })
      end)

    socket
    |> assign(
      activities: activities,
      feed_ready?: Social.list_relays() != [] and Social.list_friends() != []
    )
    |> stamp_acquisition_states()
    |> warm_activity_artwork()
  end

  # Nothing else warms an activity's identity: a title no library entity
  # owns reaches the bottom of the ladder with nothing until the
  # referenced tier is downloaded. Once per identity per mount — a fetch
  # that comes back empty (no artwork on TMDB) must not re-queue on every
  # reload. Owned async (ADR-049), so a page load never waits on TMDB.
  defp warm_activity_artwork(socket) do
    refs =
      socket.assigns.activities
      |> ActivityPosters.missing()
      |> Enum.reject(&MapSet.member?(socket.assigns.warmed_artwork, &1))

    if refs == [] or not connected?(socket) or not Capabilities.tmdb_ready?() do
      socket
    else
      socket
      |> update(:warmed_artwork, &Enum.into(refs, &1))
      |> start_async(:activity_artwork, fn ->
        Enum.each(refs, fn {tmdb_id, media_type} -> TmdbArtwork.ensure(media_type, tmdb_id) end)
      end)
    end
  end

  @impl true
  def handle_async(:activity_artwork, {:ok, _warmed}, socket), do: {:noreply, load_activities(socket)}

  def handle_async(:activity_artwork, {:exit, reason}, socket) do
    Log.warning(:social, "activity artwork warm crashed - #{inspect(reason)}")
    {:noreply, socket}
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

    %{entries: entries, has_older?: has_older?} =
      FeedEntries.build(socket.assigns.activities, now: now, window: socket.assigns.feed_window)

    assign(socket,
      feed: entries,
      feed_has_older?: has_older?,
      people:
        People.build(socket.assigns.activities, socket.assigns.friends,
          me: Identity.pubkey() != nil,
          now: now
        )
    )
  end

  defp load_friends(socket), do: assign(socket, :friends, Social.list_friends())

  defp tabs(feed, items, friends),
    do: [
      %Tab{id: :feed, label: "Feed", navigate: "/discovery", count: length(feed)},
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends", count: length(friends)}
    ]

  # Before a relay and a friend exist nothing can arrive, so the empty state
  # names what is missing rather than implying nobody wrote. The two cases
  # differ in what the reader can do next, which is why they are separate copy
  # and why only one of them carries actions.
  defp feed_empty_state(true), do: "Each friend's action is one entry, newest first."

  defp feed_empty_state(_not_ready),
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
          recommend?={@show_discovery}
        />
        <RecommendModal.recommend_modal
          subject={@recommend_subject}
          poster_url={@recommend_poster_url}
          relay_counts={@recommend_relay_counts}
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

          <.tab_strip tabs={tabs(@feed, @items, @friends)} active={@live_action} />

          <div :if={@live_action == :feed} class="space-y-2">
            <.empty_state
              :if={@feed == []}
              id="feed-empty"
              icon="hero-users"
              headline="What your friends recommend and want to watch lands here"
            >
              {feed_empty_state(@feed_ready?)}
              <:action :if={not @feed_ready?}>
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
              <:action :if={not @feed_ready?}>
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

            <FeedEntryCard.feed_entry_card :for={entry <- @feed} entry={entry} />

            <div :if={@feed_has_older?} class="flex justify-center pt-3">
              <.button id="feed-show-older" variant="dismiss" size="sm" phx-click="feed_show_older">
                Show older
              </.button>
            </div>
          </div>

          <ActionToast.action_toast
            :if={@ignore_undo}
            id="ignore-undo"
            message={"#{@ignore_undo.title.name} ignored"}
            action="Undo"
            on_action={JS.push("ignore_undo")}
            on_dismiss={JS.push("ignore_undo_dismiss") |> hide("#ignore-undo")}
          />

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

          <div :if={@live_action == :watchlist} class="space-y-2" data-nav-zone="title_rows">
            <.empty_state
              :if={@items == []}
              id="watchlist-empty"
              icon="hero-bookmark"
              headline="Titles you save land here"
            >
              Bookmark a title from its detail view and it is kept here until you
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
                Logic.row_markers(
                  %{
                    in_library?: not is_nil(row.library_owner_id),
                    acquisition_state: row.acquisition_state,
                    rung: row.rung,
                    default_grab_mode: @default_grab_mode,
                    next_air_date: row.next_air_date,
                    today: @today
                  },
                  true
                )
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
