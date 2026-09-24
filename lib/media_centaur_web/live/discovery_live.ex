defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Three
  tabs, one LiveView with a `live_action` per tab. Every title on every
  tab is a click target opening the title detail modal
  (`DetailPanel`, hosted through `TitleDetailHost` and driven by
  `?title=<media_type>-<id>` on the current tab, plus `&activity=<id>`
  when an entry or a person card opened it — refresh keeps it open, back
  closes it), where the verbs live: Play for a title the library owns,
  Download (the one-click plan) for one it does not, the bookmark and
  the tracking switches, Delete (an own activity of any kind).

  The social projections come from one list: every live activity with
  its actor (`Activities.list_activities/0`), enriched here with what
  Activities cannot know — `Library.ExternalIds.tmdb_owners/1`,
  `Discovery.rungs/0` and `Acquisition.TitleStates.for_refs/1`.

  Feed (`/discovery`, the page's default; UIDR-038, UIDR-045) — every
  author's reviews and listings, friends' and your own, one row per
  action, newest first, flat (`FeedEntries`), in one list surface; the
  newest `feed_window` of them and a *Show older* control past that
  (`feed_show_older`). The scope — Everyone, Friends, You — is the
  `?scope=` param, read in `handle_params`, patched by the pill
  (`feed_scope`) and carried by the Feed tab's link and every modal
  path, so it survives a refresh, the sidebar and the modal. A row's
  toolbar holds the verbs that live outside the modal: `feed_list` (the
  bottom rung as a toggle — List, Listed, or Following as plain state),
  `feed_download` (the one-click plan, the modal's plain Download) and,
  on a friend's row, `ignore_title` (the Ignored rung, with the Undo
  toast). An own row has neither Ignore nor Delete: it opens the modal
  speaking for its action, where Delete lives. Friends
  (`/discovery/friends`) — one `Person` card per friend and one for You
  (`People`), each with their shelves, and the add-friend form below;
  identity and relays live on the Settings page's Social section, which
  this tab points at.

  The watchlist — authored intent, and the arming surface (UIDR-035).
  Rows come from `Discovery.list_watchlist/0` (library presence derived
  live), each showing its tracking mode and, when it has one, its next
  release date as quiet markers — joined here from `ReleaseTracking`,
  because Discovery stays free of tracking (ADR-066); a row is armed
  from its modal. A row added from a friend's action carries a bare
  `activity_id`, and this page turns it into `from <nickname>`
  (`Activities.friend_activity_for/1`, which joins `Social.list_friends/0`)
  — the join neither context may make.

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
  flips a title to In library when the file lands, and to `tmdb:titles`
  so a listed title's name and poster land when the store first-contacts
  it (ADR-071).

  Declares its topics through `Live.Subscriptions`, the door the title
  detail host declares its own through, so a topic both need is
  subscribed once.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]
  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{PlanEvents, TitleStates}
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Activities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Library.Posters
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Store
  alias MediaCentaurWeb.Components.ActionToast
  alias MediaCentaurWeb.Components.Discovery.FeedEntryRow
  alias MediaCentaurWeb.Components.Discovery.PersonCard
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.IncomingLive.PlanQuery
  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.DetailPanel
  alias MediaCentaurWeb.Components.Title.Row, as: TitleRow
  alias MediaCentaurWeb.DiscoveryLive.ActivityPosters
  alias MediaCentaurWeb.DiscoveryLive.AddFriendBlock
  alias MediaCentaurWeb.DiscoveryLive.FeedEntries
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.Live.ReviewModal
  alias MediaCentaurWeb.DiscoveryLive.People
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.Live.TitleDetailHost

  require MediaCentaur.Log, as: Log
  require PursuitEvents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      Enum.reduce(
        [Discovery, Library, Social, Activities, Acquisition, Store],
        socket,
        &Subscriptions.subscribe(&2, &1)
      )

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
       feed_scope: :everyone,
       feed_ready?: false,
       people: [],
       expanded_people: MapSet.new(),
       ignore_undo: nil,
       warmed_artwork: MapSet.new(),
       today: Date.utc_today()
     )
     |> load_friends()
     |> load_items()
     |> load_activities()}
  end

  # The scope is navigation state (UIDR-045): read off the URL, so a
  # refresh, the sidebar's URL memory and the Feed tab's link all return
  # to it. Re-projecting is pure; the rows were loaded on mount.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:feed_scope, FeedEntries.parse_scope(params["scope"]))
     |> project()}
  end

  # --- TitleDetailHost ---

  # What this page alone holds is in memory: the feed's activities and
  # the snapshots embedded in them. The activity the modal speaks for,
  # the rung, friend activity and the rest the host reads by identity.
  @impl TitleDetailHost
  def page_facts(socket, ref, params) do
    case activity_row(socket, ref, Map.get(params, "activity")) do
      nil -> {nil, %{}}
      row -> {row.activity.title, %{}}
    end
  end

  @impl TitleDetailHost
  def title_detail_path(socket, query), do: discovery_path(socket, query)

  @impl TitleDetailHost
  def open_plan(socket, query), do: push_navigate(socket, to: PlanQuery.path(query))

  @impl TitleDetailHost
  def download_started(socket), do: TitleDetailHost.close_title(socket)

  # The activity the modal speaks for: the one named, else the title's
  # newest friend review (it carries the text), else any friend's
  # activity for the title. Never an own act unless named — the You card
  # and an own feed row name it; a watchlist title is not a place to
  # narrate your own broadcasts back to you.
  defp activity_row(socket, ref, nil) do
    friends = Enum.filter(socket.assigns.activities, &(activity_ref(&1) == ref and not &1.own?))
    Enum.find(friends, &(&1.activity.kind == :review)) || List.first(friends)
  end

  defp activity_row(socket, ref, activity_id) do
    Enum.find(socket.assigns.activities, &(&1.activity.id == activity_id and activity_ref(&1) == ref))
  end

  defp activity_ref(%{activity: activity}), do: {activity.tmdb_id, activity.media_type}

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

  # The pill patches the address; handle_params does the rest.
  def handle_event("feed_scope", %{"choice" => choice}, socket),
    do: {:noreply, push_patch(socket, to: feed_path(FeedEntries.parse_scope(choice)))}

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

  # The row's plain Download performs the default planning mode on the
  # default scope (season 1 for a series); the full control is in the
  # modal. The host's acquisition module owns the two paths.
  def handle_event("feed_download", %{"activity" => id}, socket) do
    case feed_entry(socket, id) do
      %FeedEntry{download_slot: :download} = entry ->
        scope = if entry.title.media_type == :tv_series, do: :first_season

        {:noreply,
         TitleDetailHost.Acquisition.start_download(
           socket,
           entry.title,
           PlanningMode.value(),
           scope,
           :stay
         )}

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

  defp entry_provenance(%FeedEntry{activity_id: id, text: text}),
    do: TitleIntent.friend_provenance(id, text)

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

  # A listed title's record landed or changed: the rows paint from the store.
  def handle_info({:tmdb_title_changed, _ref}, socket), do: {:noreply, load_items(socket)}

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
      FeedEntries.build(socket.assigns.activities,
        now: now,
        window: socket.assigns.feed_window,
        scope: socket.assigns.feed_scope
      )

    assign(socket,
      feed: entries,
      feed_has_older?: has_older?,
      feed_empty_reason: FeedEntries.empty_reason(socket.assigns.feed_scope, socket.assigns.feed_ready?),
      people:
        People.build(socket.assigns.activities, socket.assigns.friends,
          me: Identity.pubkey() != nil,
          now: now
        )
    )
  end

  defp load_friends(socket), do: assign(socket, :friends, Social.list_friends())

  defp tabs(feed, items, friends, scope),
    do: [
      %Tab{id: :feed, label: "Feed", navigate: feed_path(scope), count: length(feed)},
      %Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)},
      %Tab{id: :friends, label: "Friends", navigate: "/discovery/friends", count: length(friends)}
    ]

  # The Feed under a scope, Everyone being the bare address.
  defp feed_path(scope), do: ~p"/discovery?#{FeedEntries.scope_query(scope)}"

  # The empty state's words per diagnosis (UIDR-034): before a relay and a
  # friend exist nothing can arrive, so the copy names what is missing;
  # the You scope needs neither, so its copy is about sharing.
  defp feed_empty_headline(:everyone, :quiet),
    do: "What you and your friends review and want to watch lands here"

  defp feed_empty_headline(_scope, :nothing_shared), do: "What you review and list lands here"
  defp feed_empty_headline(_scope, _reason), do: "What your friends review and want to watch lands here"

  defp feed_empty_body(:not_ready),
    do:
      "Media Centaur reaches your friends over a relay. Add one, then add a friend by the public key they give you."

  defp feed_empty_body(:quiet), do: "Each action is one row, newest first."

  defp feed_empty_body(:nothing_shared),
    do: "A review is always shared. A title you list is shared while Share your watchlist is on."

  defp current_path(:friends), do: "/discovery/friends"
  defp current_path(:watchlist), do: "/discovery/watchlist"
  defp current_path(_action), do: "/discovery"

  # Path back to the current tab; every modal open/close patch routes
  # through this so leaving the modal never dumps the user on another
  # tab, and the Feed's scope rides along so closing the modal lands on
  # the same scope. The host hands a keyword list (`title_detail_path/2`'s
  # contract) and the scope is appended, so the modal's own params keep
  # their order.
  defp discovery_path(%{assigns: %{live_action: :feed, feed_scope: scope}}, params),
    do: ~p"/discovery?#{params ++ FeedEntries.scope_query(scope)}"

  defp discovery_path(%{assigns: %{live_action: :watchlist}}, params),
    do: ~p"/discovery/watchlist?#{params}"

  defp discovery_path(%{assigns: %{live_action: :friends}}, params), do: ~p"/discovery/friends?#{params}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path={current_path(@live_action)}
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <DetailPanel.detail_panel
          detail={@title_detail}
          state={@modal_state}
          today={@today}
          review?={@show_discovery}
          spoiler_free={@spoiler_free}
          letterboxd_links={@letterboxd_links}
          tmdb_ready={@tmdb_ready}
        />
        <ReviewModal.review_modal
          subject={@review_subject}
          poster_url={@review_poster_url}
          sentiment={@review_sentiment}
          relay_counts={@review_relay_counts}
        />
      </:overlays>
      <%!-- The modal's params are modal state: stripped from the
            remembered URL so leaving the section closes the modal rather
            than reopening it on return. --%>
      <div
        class="relative"
        data-page-behavior="discovery"
        data-nav-default-zone="discovery"
        data-nav-transient-params="title,entity,view,activity"
      >
        <div class="mx-auto w-full max-w-4xl space-y-4 pt-10">
          <.page_header title="Discovery" class="px-1" />

          <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
            <.tab_strip tabs={tabs(@feed, @items, @friends, @feed_scope)} active={@live_action} />
            <.segmented_control
              :if={@live_action == :feed}
              id="feed-scope"
              label="Scope"
              options={[{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}]}
              selected={@feed_scope}
              event="feed_scope"
            />
          </div>

          <div :if={@live_action == :feed} class="space-y-2">
            <.empty_state
              :if={@feed == []}
              id="feed-empty"
              icon="hero-users"
              headline={feed_empty_headline(@feed_scope, @feed_empty_reason)}
            >
              {feed_empty_body(@feed_empty_reason)}
              <:action :if={@feed_empty_reason == :not_ready}>
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
              <:action :if={@feed_empty_reason == :not_ready}>
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
              <:action :if={@feed_empty_reason == :nothing_shared}>
                <.button
                  variant="dismiss"
                  size="sm"
                  navigate={~p"/settings?section=social"}
                  data-nav-item
                  tabindex="0"
                >
                  Settings → Social
                </.button>
              </:action>
            </.empty_state>

            <div :if={@feed != []} id="feed-list" class="glass-inset overflow-hidden rounded-xl">
              <FeedEntryRow.feed_entry_row :for={entry <- @feed} entry={entry} />
            </div>

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
