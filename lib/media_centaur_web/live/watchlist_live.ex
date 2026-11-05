defmodule MediaCentaurWeb.WatchlistLive do
  @moduledoc """
  The Watchlist page (campaign `discovery.md`, M15): the inventory of
  every title intent, managed in place. Library is what you have; this
  page is what you want. A side view of UIDR-057 beside Library, Social
  and History, not a stage: it is not a feature (ADR-081) — the bookmark
  is on every title whatever is on, so the page is ungated and in the
  sidebar unconditionally, and it exists while Discovery is off.

  One record, two reads: Discovery draws the list by release stage to
  answer *what can I get*; this page draws it by **rung** — Auto-grab,
  Tracking, On your list, Between seasons, Ignored, Series you've watched
  (`Logic.group_order/0`) — to answer *what have I told the app to do,
  and is it right*. A followed series with nothing dated that TMDB says
  returns sits under Between seasons rather than its rung's group, so
  the shows waiting on a season announcement do not crowd the ones with
  something happening. Owned titles are
  on it, marked In library; Ignored records are on it, the one surface
  they have. Each row (`Components.Watchlist.Row`) carries the title,
  the host's markers, a friend's note, the social glyphs, the **state
  block** — what the app knows of the title's releases, from the
  calendar for a followed title and from the release stage for a
  List-only one (`Logic.state/6`) — and the **rung** as a glass select
  whose choices move the rung through the one write path
  (`TitleDetailHost.Acquisition.apply_rung/4`, as the detail's switches
  do), with Ignore and Remove. A followed series with episodes out
  carries **Caught up** in its state block — `row_caught_up`, the row's
  spelling of the detail's `caught_up`, through `ReleaseTracking.catch_up/2`
  (the latest aired episode) — and with nothing out says where the person
  stands (M16). Rows are ordered by urgency within a group. Between
  seasons, Ignored and Series you've watched are each a
  `Components.Disclosure`, closed on every visit, opened by the head or
  held open while a search is on. Ignored rows draw no poster. *Series
  you've watched* holds the series this profile finished an episode of
  (`Library.watched_tv_series/1`) that have no record and that TMDB does
  not mark Ended or Canceled (`Logic.candidates/4`): rows with no rung,
  whose select reads Not listed and adds them through the same write
  path. The page's count leaves out the Ignored rows and these. A row opens the title detail
  (`TitleDetailHost`).

  Above the groups: the type filter (All, Movies, Series) and a search
  over the names; both narrow the rows and are the page's own state, not
  the URL's. Empty, the page says why (UIDR-034): no record yet, with
  the bookmark named and a button to Discovery while it is on, else to
  Library; or nothing matching, with Show all.

  Opening the page reads the database only. The rows follow the
  watchlist, the calendars, the library's owners, the stored titles,
  friends' activity and acquisition events, debounced into one reload
  (`Logic.reloads?/1`); the page's own rung change reloads at once.

  Input: `watchlist_rows` is a TREE — UP/DOWN walk the rows across the
  groups, SELECT opens the title, RIGHT steps onto the row's rung select
  (a `data-nav-sub-item`), whose open list is the `watchlist_rung_menu`
  zone with BACK closing it; `toolbar` holds the filter and the search;
  CLEAR wipes the search (`watchlist_behavior.js`).
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.TitleStates
  alias MediaCentaur.Activities
  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB
  alias MediaCentaur.TMDB.{ReleaseStages, SeriesStatus}
  alias MediaCentaur.Watchlist
  alias MediaCentaurWeb.Components.{ActionToast, DetailPanel, Disclosure}
  alias MediaCentaurWeb.Components.Watchlist.Row
  alias MediaCentaurWeb.Live.DisclosureState
  alias MediaCentaurWeb.DownloadsLive.PlanQuery
  alias MediaCentaurWeb.Live.{ReviewModal, Subscriptions, TitleDetailHost}
  alias MediaCentaurWeb.TitleRef
  alias MediaCentaurWeb.WatchlistLive.Logic

  @reload_debounce_ms 500

  @impl true
  def mount(_params, _session, socket) do
    socket =
      Enum.reduce(
        [Watchlist, ReleaseTracking, Library, Activities, Acquisition],
        socket,
        &Subscriptions.subscribe(&2, &1)
      )

    {:ok,
     assign(socket,
       page_title: "Watchlist",
       today: Date.utc_today(),
       loaded?: false,
       reload_timer: nil,
       items: [],
       groups: [],
       filter: :all,
       query: "",
       open_menu: nil,
       empty_reason: :no_records
     )}
  end

  # The rows load once, on whichever render comes first (ADR-051).
  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, ensure_loaded(socket)}

  defp ensure_loaded(%{assigns: %{loaded?: true}} = socket), do: socket
  defp ensure_loaded(socket), do: socket |> assign(:loaded?, true) |> load_rows()

  # Every read is bounded and local: the records, then for their refs
  # the tracking items with their calendars, the release stages, the
  # series statuses, the acquisition states and the activity rows.
  defp load_rows(socket) do
    today = socket.assigns.today
    listed = Watchlist.list_intents()
    refs = Enum.map(listed, &{&1.intent.tmdb_id, &1.intent.media_type})

    tracking = Map.new(ReleaseTracking.list_all_items(), &{{&1.tmdb_id, &1.media_type}, &1})

    items =
      Logic.items(
        listed,
        tracking,
        ReleaseStages.for_refs(refs, today),
        SeriesStatus.for_refs(refs),
        TitleStates.for_refs(refs),
        Activities.activity_for(refs),
        today
      )

    socket |> assign(:items, items ++ watched_rows(socket, refs)) |> assign_groups()
  end

  # The series this profile watched that have no record yet, read from
  # the library and the store — the closed *Series you've watched* group.
  defp watched_rows(socket, record_refs) do
    watched = Library.watched_tv_series(socket.assigns.profile.id)

    watched_refs =
      for %{tmdb_id: tmdb_id} <- watched, {id, ""} <- [Integer.parse(tmdb_id)], do: {id, :tv_series}

    Logic.candidates(
      watched,
      MapSet.new(record_refs),
      TMDB.Store.snapshots(watched_refs),
      SeriesStatus.for_refs(watched_refs)
    )
  end

  defp assign_groups(socket) do
    %{items: items, filter: filter, query: query, open_menu: open_menu} = socket.assigns
    shown = Logic.narrow(items, filter, query)

    assign(socket,
      groups: shown |> Logic.mark_open(open_menu) |> Logic.groups(),
      empty_reason: Logic.empty_reason(items, shown)
    )
  end

  @impl true
  def handle_event("filter", %{"choice" => choice}, socket),
    do: {:noreply, socket |> assign(:filter, Logic.parse_filter(choice)) |> assign_groups()}

  def handle_event("search", %{"value" => query}, socket),
    do: {:noreply, socket |> assign(:query, query) |> assign_groups()}

  def handle_event("show_all", _params, socket),
    do: {:noreply, socket |> assign(filter: :all, query: "") |> assign_groups()}

  # One rung menu open at a time: the trigger toggles its own, a click
  # outside or BACK closes whichever is open.
  def handle_event("rung_menu_toggle", %{"ref" => ref}, socket) do
    open = if socket.assigns.open_menu != ref, do: ref
    {:noreply, socket |> assign(:open_menu, open) |> assign_groups()}
  end

  def handle_event("rung_menu_close", _params, socket),
    do: {:noreply, socket |> assign(:open_menu, nil) |> assign_groups()}

  # The row's Caught up is the detail's caught_up by another trigger: the
  # one write path, then the rows re-read at once.
  def handle_event("row_caught_up", %{"ref" => param}, socket) do
    with {:ok, {tmdb_id, :tv_series}} <- TitleRef.parse(param),
         %ReleaseTracking.Item{} = item <- ReleaseTracking.get_item_by_tmdb(tmdb_id, :tv_series),
         :ok <- ReleaseTracking.catch_up(item, :latest) do
      {:noreply, load_rows(socket)}
    else
      _not_followed_or_refused -> {:noreply, socket}
    end
  end

  # The row's choice is the detail's set_rung by another trigger: the
  # same write path, then the rows re-read at once — the broadcast that
  # follows reloads again, debounced, and changes nothing.
  def handle_event("rung_choice", %{"choice" => choice, "ref" => param}, socket) do
    socket = assign(socket, :open_menu, nil)

    with rung when not is_nil(rung) <- Logic.parse_choice(choice),
         {:ok, ref} <- TitleRef.parse(param),
         %Row.Item{title: title} <- Enum.find(socket.assigns.items, &(&1.ref == ref)) do
      {:noreply,
       socket
       |> TitleDetailHost.Acquisition.apply_rung(title, rung, %{})
       |> load_rows()}
    else
      _unknown -> {:noreply, assign_groups(socket)}
    end
  end

  @impl true
  def handle_info(:reload_rows, socket),
    do: {:noreply, socket |> assign(:reload_timer, nil) |> load_rows()}

  # The title detail host's hook has already refreshed an open detail for
  # these broadcasts; the page re-reads its rows for the ones that change
  # them, coalescing a burst into one read.
  def handle_info(message, socket) do
    if Logic.reloads?(message) and socket.assigns.loaded?,
      do: {:noreply, debounce(socket, :reload_timer, :reload_rows, @reload_debounce_ms)},
      else: {:noreply, socket}
  end

  # --- TitleDetailHost ---

  # Every row's title is a store identity the host reads on its own; the
  # row's snapshot is what this page holds.
  @impl TitleDetailHost
  def page_facts(socket, ref, _params) do
    case Enum.find(socket.assigns.items, &(&1.ref == ref)) do
      %Row.Item{title: title} -> {title, %{}}
      nil -> {nil, %{}}
    end
  end

  @impl TitleDetailHost
  def title_detail_path(_socket, []), do: ~p"/watchlist"
  def title_detail_path(_socket, query), do: ~p"/watchlist?#{query}"

  @impl TitleDetailHost
  def open_plan(socket, query), do: push_navigate(socket, to: PlanQuery.path(query))

  @impl TitleDetailHost
  def download_started(socket), do: TitleDetailHost.close_title(socket)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      profile={@profile}
      profiles={@profiles}
      viewing_layer={assigns[:viewing_layer]}
      features={@features}
      flash={@flash}
      current_path="/watchlist"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <%!-- Before the detail: the input system takes the first open
              [data-detail-mode=modal] in DOM order as the active overlay, so the
              raised Review modal must precede the detail it opens over. --%>
        <ReviewModal.review_modal state={@review} armed_gesture={@armed_gesture} />
        <DetailPanel.detail_panel
          detail={@title_detail}
          state={@modal_state}
          armed_gesture={@armed_gesture}
          today={@today}
          review?={:social in @features}
          spoiler_free={@spoiler_free}
          letterboxd_links={@letterboxd_links}
          tmdb_ready={@tmdb_ready}
          finished_id={@finished_id}
        />
      </:overlays>
      <%!-- The modal's params are modal state: stripped from the remembered
            URL so leaving the page closes the modal rather than reopening
            it on return. --%>
      <div
        class="mx-auto max-w-5xl space-y-6 py-6"
        data-page-behavior="watchlist"
        data-nav-default-zone="watchlist"
        data-nav-transient-params="title,entity,view,activity"
      >
        <ActionToast.action_toast
          :if={@ignore_undo}
          id="ignore-undo"
          message={"#{@ignore_undo.title.name} ignored"}
          action="Undo"
          on_action={JS.push("ignore_undo")}
          on_dismiss={JS.push("ignore_undo_dismiss") |> hide("#ignore-undo")}
        />

        <.page_header title="Watchlist">
          <:subtitle :if={Logic.listed_count(@items) > 0}>
            {count_label(Logic.listed_count(@items))}
          </:subtitle>
        </.page_header>

        <%!-- The filter and the search are bookkeeping over the rows: with
              no record at all they narrow nothing, so they render once
              there is a record. --%>
        <div
          :if={@empty_reason != :no_records}
          data-nav-zone="toolbar"
          class="flex flex-wrap items-center gap-3"
        >
          <.segmented_control
            id="watchlist-filter"
            label="Type"
            options={[{:all, "All"}, {:movies, "Movies"}, {:series, "Series"}]}
            selected={@filter}
            event="filter"
          />
          <input
            id="watchlist-search"
            type="search"
            class="input input-sm w-64"
            placeholder="Search your list"
            value={@query}
            phx-change="search"
            phx-debounce="300"
            name="value"
            data-nav-item
            tabindex="0"
          />
        </div>

        <.empty_state
          :if={@empty_reason == :no_records}
          id="watchlist-empty"
          icon="hero-bookmark"
          headline="Your list starts with a bookmark"
          data-nav-zone="watchlist_rows"
        >
          Press the bookmark on any title — in the library, on Discovery, in a search — and it
          lands here with what the app knows about its releases.
          <:action>
            <.button
              :if={:discovery in @features}
              variant="primary"
              size="sm"
              navigate={~p"/discovery"}
              data-nav-item
              tabindex="0"
            >
              Open Discovery
            </.button>
            <.button
              :if={:discovery not in @features}
              variant="primary"
              size="sm"
              navigate={~p"/library"}
              data-nav-item
              tabindex="0"
            >
              Browse the library
            </.button>
          </:action>
        </.empty_state>

        <.empty_state
          :if={@empty_reason == :nothing_matches}
          id="watchlist-nothing-matches"
          headline="Nothing on your list matches"
          data-nav-zone="watchlist_rows"
        >
          <:action>
            <.button variant="dismiss" size="sm" phx-click="show_all" data-nav-item tabindex="0">
              Show all
            </.button>
          </:action>
        </.empty_state>

        <div :if={@groups != []} data-nav-zone="watchlist_rows" class="space-y-8">
          <%= for group <- @groups do %>
            <%!-- A closed group — Between seasons, Ignored, Series you've
                  watched — is closed on every visit, opened on purpose,
                  held open while a search is on. --%>
            <Disclosure.disclosure
              :if={group.closed?}
              id={"watchlist-group-#{group.id}"}
              open={
                Logic.group_open?(
                  DisclosureState.open?(@disclosures, "watchlist-group-#{group.id}"),
                  @query
                )
              }
              variant={:quiet}
              class="px-4"
              data-group={group.id}
            >
              <:head>
                <span class="font-medium uppercase tracking-wider">{group.label}</span>
                <span class="normal-case tracking-normal">{length(group.items)}</span>
              </:head>
              <div class="-mx-4 divide-y divide-base-content/8">
                <Row.watchlist_row
                  :for={item <- group.items}
                  item={item}
                  today={@today}
                  caught_up?={Logic.caught_up_offered?(item)}
                />
              </div>
            </Disclosure.disclosure>
            <section
              :if={not group.closed?}
              id={"watchlist-group-#{group.id}"}
              data-group={group.id}
            >
              <h2 class="mb-2 px-4 text-sm font-medium uppercase tracking-wider text-base-content/55">
                {group.label}
                <span class="ml-1 normal-case tracking-normal text-base-content/55">
                  {length(group.items)}
                </span>
              </h2>
              <div class="divide-y divide-base-content/8">
                <Row.watchlist_row
                  :for={item <- group.items}
                  item={item}
                  today={@today}
                  caught_up?={Logic.caught_up_offered?(item)}
                />
              </div>
            </section>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp count_label(1), do: "1 title"
  defp count_label(count), do: "#{count} titles"
end
