defmodule MediaCentaurWeb.SocialLive do
  @moduledoc """
  The Discovery page — the surface every candidate source lands on. Two
  tabs, one LiveView with a `live_action` per tab. Every title on every
  tab is a click target opening the title detail modal
  (`DetailPanel`, hosted through `TitleDetailHost` and driven by
  `?title=<media_type>-<id>` on the current tab, plus `&activity=<id>`
  when a row or a person card opened it — refresh keeps it open, back
  closes it), where the verbs live: Play for a title the library owns,
  Download (the one-click plan) for one it does not, the bookmark and
  the tracking switches, Delete (an own activity of any kind).

  The social projections come from one list: every live activity with
  its actor (`Activities.list_activities/0`), enriched here with what
  Activities cannot know — `Library.ExternalIds.tmdb_owners/1`,
  `Discovery.rungs/0` and `Acquisition.TitleStates.for_refs/1`.

  Feed (`/social`, the page's default; UIDR-038, UIDR-045, UIDR-046)
  — every author's reviews and listings, friends' and your own, one
  row per action, newest first, flat (`FeedEntries`, `FeedRow`), in a
  column at the layout's full width beside the rail: person cards
  (`PersonCard` at the rail's width, `People.rail/1` — You first, then
  friends by latest act, capped at eight with *All N friends*), drawn on
  the Feed, folded away by CSS below 1600px of content (the LiveView
  never learns the width). Paging is a window with a cap and a queued
  head: the newest `feed_window` rows (twenty; *Show older* adds twenty
  to sixty, then `#feed-cap` says so), and
  `feed_head` — nil while the column's top is in view, so an arrival
  prepends live; else the newest row shown, set by the `FeedHead`
  hook's `feed_scrolled`, cleared by `feed_at_top` and by "N new"
  (`feed_show_new`, which also scrolls the window to the top). The
  scope — Everyone, Friends, You — is the
  `?scope=` param, read in `handle_params`, patched by the pill
  (`feed_scope`) and carried by every modal path and, while the Feed is
  the active tab, by the Feed tab's link, so it survives a refresh, the
  sidebar's section memory and the modal. A row's toolbar holds the
  verbs that live outside the modal: `feed_list` (the bottom rung as a
  toggle — List, Listed, or Following as plain state),
  `feed_download` (the one-click plan, the modal's plain Download) and,
  on a friend's row, `ignore_title` (the Ignored rung, with the Undo
  toast). An own row has neither Ignore nor Delete: it opens the modal
  speaking for its action, where Delete lives. Friends
  (`/social/friends`) — a grid of page cards, one per friend and one
  for You (`People`), each their latest acts as posters under act slots;
  a press opens a card in place (`toggle_person`, the `opened_people`
  set), and `?person=<card id>` — where a rail card's press lands
  (`open_person`) — opens that card and hands it focus on mount; the
  add-friend form below; identity and relays live on the Settings
  page's Social section, which this tab points at. The watchlist itself
  is Incoming's first tab (UIDR-050).

  A listing or an ignore made from a row carries that row's activity
  as provenance (`TitleIntent.friend_provenance/2`), the way the
  modal's ladder does. Because Ignore shows no state to reverse, it
  gets an undo toast (`ignore_undo` restores the rung the title had;
  `ignore_undo_dismiss` clears the toast, by click or by expiry).

  Every feed row carries its acquisition state (Planning / Downloading /
  Needs review) stamped from one `TitleStates` read per load; the page
  subscribes to `acquisition:updates` so a one-click download's progress
  lands without a reload, the way `library:updates` flips a title to In
  library when the file lands.

  Declares its topics through `Live.Subscriptions`, the door the title
  detail host declares its own through, so a topic both need is
  subscribed once.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  import MediaCentaurWeb.Components.TabStrip, only: [tab_strip: 1]

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.{PlanEvents, TitleStates}
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentaur.Activities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Library
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Library.Artwork
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Hue
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaurWeb.Components.ActionToast
  alias MediaCentaurWeb.Components.Social.FeedRow
  alias MediaCentaurWeb.Components.Social.PersonCard
  alias MediaCentaurWeb.Components.TabStrip.Tab
  alias MediaCentaurWeb.IncomingLive.PlanQuery
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.DetailPanel
  alias MediaCentaurWeb.SocialLive.ActivityArtwork
  alias MediaCentaurWeb.SocialLive.AddFriendBlock
  alias MediaCentaurWeb.SocialLive.FeedEntries
  alias MediaCentaurWeb.Live.ReviewModal
  alias MediaCentaurWeb.SocialLive.People
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.Live.TitleDetailHost

  require MediaCentaur.Log, as: Log
  require PursuitEvents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      Enum.reduce(
        [Discovery, Library, Social, Activities, Acquisition],
        socket,
        &Subscriptions.subscribe(&2, &1)
      )

    {:ok,
     socket
     |> assign(:page_title, "Social")
     |> assign(
       activities: [],
       feed: [],
       feed_has_older?: false,
       feed_window: FeedEntries.page_size(),
       feed_scope: :everyone,
       feed_ready?: false,
       feed_head: nil,
       feed_queued: 0,
       feed_at_cap?: false,
       rail: %{cards: [], hidden: 0},
       landed_person: nil,
       people: [],
       opened_people: MapSet.new(),
       ignore_undo: nil,
       warmed_artwork: MapSet.new(),
       today: Date.utc_today()
     )
     |> load_people()
     |> load_activities()}
  end

  # The scope is navigation state (UIDR-045): read off the URL, so a
  # refresh and the sidebar's URL memory return to it, and the Feed tab's
  # link carries it while the Feed is active. Re-projecting is pure; the
  # rows were loaded on mount.
  @impl true
  def handle_params(params, _uri, socket) do
    scope = FeedEntries.parse_scope(params["scope"])
    landed = if socket.assigns.live_action == :friends, do: params["person"]

    {:noreply,
     socket
     |> reset_head_on_scope_change(scope)
     |> assign(feed_scope: scope, landed_person: landed)
     |> open_landed(landed)
     |> project()}
  end

  # A new scope is a new column: the reader is at its top.
  defp reset_head_on_scope_change(%{assigns: %{feed_scope: scope}} = socket, scope), do: socket
  defp reset_head_on_scope_change(socket, _scope), do: assign(socket, :feed_head, nil)

  defp open_landed(socket, nil), do: socket
  defp open_landed(socket, id), do: update(socket, :opened_people, &MapSet.put(&1, id))

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
  def title_detail_path(socket, query), do: social_path(socket, query)

  @impl TitleDetailHost
  def open_plan(socket, query), do: push_navigate(socket, to: PlanQuery.path(query))

  @impl TitleDetailHost
  def download_started(socket), do: TitleDetailHost.close_title(socket)

  # The activity the modal speaks for: the one named, else the title's
  # newest friend review (it carries the text), else any friend's
  # activity for the title. Never an own act unless named — the You card
  # and an own feed row name it; a `?title=` deep link on the Feed is not
  # a place to narrate your own broadcasts back to you.
  defp activity_row(socket, ref, nil) do
    friends = Enum.filter(socket.assigns.activities, &(activity_ref(&1) == ref and not &1.author.own?))
    Enum.find(friends, &(&1.activity.kind == :review)) || List.first(friends)
  end

  defp activity_row(socket, ref, activity_id) do
    Enum.find(socket.assigns.activities, &(&1.activity.id == activity_id and activity_ref(&1) == ref))
  end

  defp activity_ref(%{activity: activity}), do: {activity.tmdb_id, activity.media_type}

  @impl true
  # The page card's press opens it in place; the same press closes it.
  def handle_event("toggle_person", %{"id" => id}, socket) do
    {:noreply,
     update(socket, :opened_people, fn opened ->
       if MapSet.member?(opened, id), do: MapSet.delete(opened, id), else: MapSet.put(opened, id)
     end)}
  end

  # The rail card's press goes to the person on the Friends page.
  def handle_event("open_person", %{"id" => id}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/social/friends?person=#{id}")}

  # --- the roster: the add form and the opened card's foot ---
  #
  # None of these reloads the people on success. `Social` broadcasts the
  # change (`FriendAdded`, `FriendChanged`, `FriendRemoved`) over local
  # PubSub, synchronously, so the message is in this LiveView's mailbox
  # before the handler returns, and the `@people_tags` `handle_info` does
  # the one reload — the same path a change from another tab takes. A
  # no-op (a key already on the roster, the same name again) broadcasts
  # nothing, and there is nothing to reload. In a test the click's reply
  # carries no diff; read the result with `has_element?`/`render`, not
  # `render_click`'s return.

  def handle_event("add_friend", %{"key" => key, "name" => name}, socket) do
    case Social.add_friend(key, name) do
      {:ok, _friend} -> {:noreply, socket}
      {:error, :own_key} -> {:noreply, put_flash(socket, :error, "That is your own key")}
      {:error, _invalid} -> {:noreply, put_flash(socket, :error, "That is not a valid public key")}
    end
  end

  # The opened card's foot: the reader's name for the friend; a blank clears it.
  def handle_event("set_friend_name", %{"pubkey" => pubkey, "name" => name}, socket) do
    case Social.set_name_override(pubkey, name) do
      {:ok, _friend} -> {:noreply, socket}
      {:error, :not_a_friend} -> {:noreply, flash_not_a_friend(socket)}
    end
  end

  # The opened card's foot: whether this reader shows the friend's
  # published picture; `show` is the value to set.
  def handle_event("set_show_avatar", %{"pubkey" => pubkey, "show" => show}, socket) do
    case Social.set_show_avatar(pubkey, show == "true") do
      {:ok, _friend} -> {:noreply, socket}
      {:error, :not_a_friend} -> {:noreply, flash_not_a_friend(socket)}
    end
  end

  # The opened card's foot: the reader's hue for the friend; empty is
  # Theirs, clearing it. A swatch's click and the slider's change carry
  # the same two keys.
  def handle_event("set_hue_override", %{"pubkey" => pubkey, "hue" => hue}, socket) do
    with {:ok, hue} <- Hue.parse(hue),
         {:ok, _friend} <- Social.set_hue_override(pubkey, hue) do
      {:noreply, socket}
    else
      {:error, :not_a_friend} -> {:noreply, flash_not_a_friend(socket)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("remove_friend", %{"pubkey" => pubkey}, socket) do
    :ok = Social.remove_friend(pubkey)
    {:noreply, socket}
  end

  # --- the Feed's toolbar — see the moduledoc ---

  def handle_event("feed_show_older", _params, socket) do
    {:noreply,
     socket
     |> update(:feed_window, &min(&1 + FeedEntries.page_size(), FeedEntries.cap()))
     |> project()}
  end

  # The FeedHead hook's crossings. Scrolled in, the window freezes at the
  # newest row shown and arrivals queue; back at the top, they land.
  def handle_event("feed_scrolled", _params, socket) do
    head =
      case socket.assigns.feed do
        [first | _rest] -> first.activity_id
        [] -> nil
      end

    {:noreply, assign(socket, :feed_head, head)}
  end

  def handle_event("feed_at_top", _params, socket),
    do: {:noreply, socket |> assign(:feed_head, nil) |> project()}

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
  def handle_info({:title_intent_changed, _event}, socket), do: {:noreply, load_activities(socket)}

  def handle_info({:entities_changed, %Library.Events.EntitiesChanged{}}, socket),
    do: {:noreply, load_activities(socket)}

  def handle_info({tag, _event}, socket)
      when tag in [:activity_received, :activity_sent, :activity_deleted] do
    {:noreply, load_activities(socket)}
  end

  def handle_info({tag, _event}, socket) when tag in [:relay_added, :relay_removed] do
    {:noreply, load_activities(socket)}
  end

  @people_tags [:friend_added, :friend_removed, :friend_changed, :identity_changed, :profile_updated]

  # The roster, the identity or a published name changed: the people are
  # reread and the rows redrawn under them.
  def handle_info({tag, _event}, socket) when tag in @people_tags do
    {:noreply, socket |> load_people() |> load_activities()}
  end

  def handle_info(%PlanEvents.Changed{}, socket), do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(%struct{}, socket) when PursuitEvents.is_event(struct),
    do: {:noreply, stamp_acquisition_states(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # The activity row's decoration: Activities owns the record and its
  # author; watchlist and library presence are derived here, live,
  # from the contexts that own them. Both tabs project from this list.
  # The poster too — an activity snapshot carries no poster path, so
  # only this page knows which artwork tier the title lives in
  # (`ActivityArtwork`).
  defp load_activities(socket) do
    rows = Activities.list_activities()

    owners =
      ExternalIds.tmdb_owners(Enum.map(rows, &{&1.activity.tmdb_id, &1.activity.media_type}))

    refs = ActivityArtwork.library_refs(owners)
    library_artwork = Map.new(ActivityArtwork.roles(), &{&1, Artwork.urls_by_refs(refs, &1)})
    rungs = Discovery.rungs()

    activities =
      Enum.map(rows, fn %{activity: activity} = row ->
        ref = {activity.tmdb_id, activity.media_type}

        row
        |> Map.merge(ActivityArtwork.urls(activity, owners, library_artwork))
        |> Map.merge(%{library_owner_id: Map.get(owners, ref), rung: Map.get(rungs, ref)})
      end)

    socket
    |> assign(
      activities: activities,
      feed_ready?: Social.list_relays() != [] and socket.assigns.friend_count > 0
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
      |> ActivityArtwork.missing()
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

  # Acquisition state per row from one read over the rows' refs; the
  # rows are the one representation, so the projections and the open
  # detail re-read them.
  defp stamp_acquisition_states(socket) do
    refs = Enum.map(socket.assigns.activities, &activity_ref/1)
    states = TitleStates.for_refs(Enum.uniq(refs))

    socket
    |> update(:activities, fn activities ->
      Enum.map(activities, &Map.put(&1, :acquisition_state, Map.get(states, activity_ref(&1))))
    end)
    |> project()
    |> TitleDetailHost.refresh_title_detail()
  end

  defp project(socket) do
    now = DateTime.utc_now()

    %{entries: entries, has_older?: has_older?, at_cap?: at_cap?, queued: queued} =
      FeedEntries.build(socket.assigns.activities,
        now: now,
        window: socket.assigns.feed_window,
        scope: socket.assigns.feed_scope,
        head: socket.assigns.feed_head
      )

    people = People.build(socket.assigns.activities, socket.assigns.people_by_pubkey, now: now)

    assign(socket,
      feed: entries,
      feed_has_older?: has_older?,
      feed_at_cap?: at_cap?,
      feed_queued: queued,
      feed_empty_reason: FeedEntries.empty_reason(socket.assigns.feed_scope, socket.assigns.feed_ready?),
      people: people,
      rail: People.rail(people)
    )
  end

  # The known people (`Social.people/0`), the reader included when an
  # identity exists: the cards are built from the map, the tab's count
  # and the feed's readiness are derived from it. The roster is held once.
  defp load_people(socket) do
    people = Social.people()

    assign(socket,
      people_by_pubkey: people,
      friend_count: Enum.count(people, fn {_pubkey, person} -> not person.own? end)
    )
  end

  # The foot acted on a key the roster no longer holds — removed in
  # another tab between the card's open and the click.
  defp flash_not_a_friend(socket), do: put_flash(socket, :error, "That friend is no longer on your list")

  defp tabs(feed, friend_count, scope),
    do: [
      %Tab{id: :feed, label: "Feed", navigate: feed_path(scope), count: length(feed)},
      %Tab{id: :friends, label: "Friends", navigate: "/social/friends", count: friend_count}
    ]

  # The Feed under a scope, Everyone being the bare address.
  defp feed_path(scope), do: ~p"/social?#{FeedEntries.scope_query(scope)}"

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

  defp current_path(:friends), do: "/social/friends"
  defp current_path(_action), do: "/social"

  # Path back to the current tab; every modal open/close patch routes
  # through this so leaving the modal never dumps the user on another
  # tab, and the Feed's scope rides along so closing the modal lands on
  # the same scope. The host hands a keyword list (`title_detail_path/2`'s
  # contract) and the scope is appended, so the modal's own params keep
  # their order.
  defp social_path(%{assigns: %{live_action: :feed, feed_scope: scope}}, params),
    do: ~p"/social?#{params ++ FeedEntries.scope_query(scope)}"

  defp social_path(%{assigns: %{live_action: :friends}}, params), do: ~p"/social/friends?#{params}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      show_social={@show_social}
      show_apps={@show_apps}
      flash={@flash}
      current_path={current_path(@live_action)}
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
      full_width={@live_action == :friends}
    >
      <:overlays>
        <DetailPanel.detail_panel
          detail={@title_detail}
          state={@modal_state}
          armed_gesture={@armed_gesture}
          today={@today}
          review?={@show_social}
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
        data-page-behavior="social"
        data-nav-default-zone="social"
        data-nav-transient-params="title,entity,view,activity"
      >
        <%!-- The same fixed scrim every page but Home carries (UIDR-033),
              behind the columns so it darkens the ground, never the posters. --%>
        <div class="page-side-dim" aria-hidden="true"></div>

        <%!-- Library's frame: the page header at the top of the page, the
              controls under it. The Feed sits in the layout's 1280px
              container like every page but Home — a poster row wants a
              reading measure, not the panel — while the Friends grid opts
              out to the full width for its two columns. --%>
        <div class="social-page relative z-[1] w-full">
          <.page_header title="Social" class="mb-5" />

          <%!-- The head row shares the columns' grid: the strip and the
                scope pill in the feed column's cell, the hairline under
                both columns (UIDR-046). --%>
          <div class="social-columns social-head mb-4">
            <div class="social-head-cell">
              <.tab_strip
                tabs={tabs(@feed, @friend_count, @feed_scope)}
                active={@live_action}
              />
              <.segmented_control
                :if={@live_action == :feed}
                id="feed-scope"
                label="Scope"
                options={[{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}]}
                selected={@feed_scope}
                event="feed_scope"
              />
            </div>
          </div>

          <div class="social-columns">
            <div class="min-w-0">
              <div :if={@live_action == :feed} class="relative">
                <%!-- The column's head: the FeedHead hook reports it leaving and
                  returning to the viewport. Out of the flow, so the first
                  row's top is the column's top, level with the rail. --%>
                <div
                  id="feed-head"
                  phx-hook="FeedHead"
                  phx-update="ignore"
                  class="absolute left-0 top-0 h-px w-px"
                >
                </div>
                <%!-- "N new" holds what arrived while the reader was scrolled in:
                  a zero-height sticky anchor, so the control rides 12px under
                  the viewport's top without moving the column. --%>
                <div :if={@feed_queued > 0} class="sticky top-3 z-10 h-0">
                  <button
                    id="feed-new"
                    type="button"
                    class="absolute left-4 top-0 inline-flex h-8 cursor-pointer items-center gap-1.5 rounded-full bg-[oklch(13%_0.02_264/0.94)] px-3 text-sm text-base-content/85 shadow-[0_4px_16px_oklch(0%_0_0/0.5)]"
                    phx-click={JS.dispatch("feed:scroll-top", to: "#feed-head")}
                  >
                    <.icon name="hero-arrow-up" class="size-4" /> {@feed_queued} new
                  </button>
                </div>
                <div class="space-y-2">
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
                        navigate={~p"/social/friends"}
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

                  <div :if={@feed != []} id="feed-list" class="divide-y divide-base-content/10">
                    <FeedRow.feed_row :for={entry <- @feed} entry={entry} />
                  </div>

                  <div :if={@feed_has_older?} class="pl-4 pt-2.5">
                    <.button
                      id="feed-show-older"
                      variant="dismiss"
                      size="sm"
                      phx-click="feed_show_older"
                    >
                      Show older
                    </.button>
                  </div>
                  <p
                    :if={@feed_at_cap?}
                    id="feed-cap"
                    class="pl-4 pt-2.5 text-sm text-base-content/65"
                  >
                    That's the last sixty.
                  </p>
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
                <div :if={@people != []} id="friends-grid" class="friends-grid" data-nav-zone="people">
                  <PersonCard.person_card
                    :for={card <- @people}
                    person={card.person}
                    acts={card.acts}
                    width={:page}
                    opened?={MapSet.member?(@opened_people, PersonCard.dom_id(card.person))}
                    landed?={PersonCard.dom_id(card.person) == @landed_person}
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
            </div>
            <.rail :if={@live_action == :feed} rail={@rail} friend_count={@friend_count} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # The rail (UIDR-046): the roster's summary beside the Feed — You
  # first, then the seven most recent, and "All N friends" when the cap
  # hides anyone. Page composition, not a reusable component; nothing
  # here is a nav item until the hardening pass.
  attr :rail, :map, required: true, doc: "`People.rail/1`: the cards shown and how many the cap hid"
  attr :friend_count, :integer, required: true, doc: "for All N friends"

  defp rail(assigns) do
    ~H"""
    <aside
      :if={@rail.cards != []}
      id="feed-rail"
      class="social-rail divide-y divide-base-content/10"
    >
      <PersonCard.person_card
        :for={card <- @rail.cards}
        person={card.person}
        acts={card.acts}
        width={:rail}
      />
      <.link
        :if={@rail.hidden > 0}
        id="feed-rail-all"
        navigate={~p"/social/friends"}
        class="block pl-3.5 pt-3 text-sm text-base-content/70 hover:text-base-content/90"
      >
        All {@friend_count} friends
      </.link>
    </aside>
    """
  end
end
