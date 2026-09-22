defmodule MediaCentaurWeb.LibraryLive do
  @moduledoc """
  Library Browse page — the full entity catalog as a poster grid with
  type tabs, sort, and text filter. Selecting an entity opens a
  DetailPanel detail overlay. Mounted at `/library`.

  ## Read path (Library Schema v2 Phase 3.1)

  The grid reads from the `Library.Views.Browse` ETS projection
  (ADR-041) — pre-shaped `BrowseItem` structs in recent-first
  (`inserted_at desc`) order, each carrying `available?` and a poster
  URL only when its storage is reachable (`Views.ItemAvailability`).
  Progress lives in a per-id map populated via the bulk context function
  `Library.ProgressRecords.summaries/1`. The mount issues a bounded
  number of queries that does not scale with catalog size.

  ## Update path

  Subscriptions split by concern:

    * `library:views` — projection refresh broadcasts. On
      `{:library_view_updated, :browse}` the LiveView re-reads
      `Views.browse/0` (microsecond ETS lookup), the progress map, and
      the per-directory status behind the offline banner. A drive
      mounting or unmounting arrives here too: the projection rebuilds
      on the availability event, so the offline cards flip to artwork
      as a DOM change the browser fetches.
    * `library:updates` — wired by the EntityModal hook for the
      selected modal state; the grid no longer reacts directly.
    * `playback:events` — pulse dot + flash on `playback_state_changed`
      / `playback_failed`.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.Live.TitleDetailHost
  use MediaCentaurWeb.Live.SpoilerFreeAware
  use MediaCentaurWeb.Live.LibraryCardInfoAware
  use MediaCentaurWeb.Live.CardPlayButtonAware
  use MediaCentaurWeb.Live.LetterboxdLinksAware

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Settings.Config

  alias MediaCentaur.{
    Library,
    Library.MediaFileAvailability
  }

  alias MediaCentaur.Pipeline.Stats

  alias MediaCentaurWeb.Components.LibraryCards
  alias MediaCentaurWeb.Live.ReviewModal

  import MediaCentaurWeb.LibraryHelpers
  import MediaCentaurWeb.LibraryFormatters

  alias MediaCentaurWeb.Components.DetailPanel
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.Live.TitleDetailHost

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Library")

    # Declared through the one door: the title detail host declares
    # `library:updates` and `playback:events` for the modal, this page
    # the projections, config and the pipeline's stats.
    socket =
      Enum.reduce(
        [Library.Views, Config, MediaCentaur.Pipeline.Stats],
        socket,
        &Subscriptions.subscribe(&2, &1)
      )

    {:ok,
     socket
     |> assign(
       today: Date.utc_today(),
       loaded?: false,
       entries: [],
       progress_by_id: %{},
       visible_ids: MapSet.new(),
       active_tab: :all,
       sort_order: :recent,
       sort_open: false,
       filter_text: "",
       counts: %{all: 0, movies: 0, tv: 0},
       grid_count: 0,
       unavailable_count: 0,
       media_dirs: Config.get(:media_dirs) || [],
       media_dirs_configured: media_dirs_configured?(),
       dir_status: MediaFileAvailability.dir_status(),
       pipeline_queue_depth: 0,
       scanning: false
     )
     |> stream_configure(:grid, dom_id: &"entity-#{&1.id}")
     |> stream(:grid, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    was_loaded? = socket.assigns.loaded?
    socket = ensure_loaded(socket)
    just_loaded = not was_loaded? and socket.assigns.loaded?

    tab = parse_tab(params["tab"])
    sort = parse_sort(params["sort"])
    filter_text = params["filter"] || ""

    grid_changed =
      just_loaded ||
        tab != socket.assigns.active_tab ||
        sort != socket.assigns.sort_order ||
        filter_text != socket.assigns.filter_text

    socket =
      socket
      |> assign(
        active_tab: tab,
        sort_order: sort,
        filter_text: filter_text
      )
      |> then(fn socket -> if grid_changed, do: cache_visible_ids(socket), else: socket end)
      |> then(fn socket -> if grid_changed, do: reset_stream(socket), else: socket end)

    {:noreply, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(
           %{socket | assigns: Map.put(socket.assigns, :active_tab, parse_tab(tab))},
           %{}
         )
     )}
  end

  def handle_event("toggle_sort", _params, socket), do: {:noreply, update(socket, :sort_open, &(!&1))}

  def handle_event("close_sort", _params, socket) do
    {:noreply, assign(socket, sort_open: false)}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    sort = parse_sort(sort)

    socket = assign(socket, sort_open: false)

    {:noreply,
     push_patch(socket,
       to: build_path(%{socket | assigns: Map.put(socket.assigns, :sort_order, sort)}, %{})
     )}
  end

  def handle_event("filter", %{"filter_text" => text}, socket) do
    {:noreply,
     push_patch(socket,
       to: build_path(%{socket | assigns: Map.put(socket.assigns, :filter_text, text)}, %{}),
       replace: true
     )}
  end

  # Inline × on the search box — drop only the text filter, preserving the
  # active tab and sort.
  def handle_event("clear_filter", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{filter: ""}))}
  end

  # "Clear filters" in the no-matches empty state — reset every filter that
  # can hide a card (tab, text) so the grid is guaranteed to repopulate;
  # sort is a presentation choice, not a filter, so it stays.
  def handle_event("reset_filters", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, %{tab: :all, filter: ""}))}
  end

  # Owned async so the socket stays responsive — a synchronous call would
  # block render and the "Scanning…" label would never appear — and so the
  # scan is cancelled with the LiveView and awaitable in tests (ADR-049,
  # MC0019). Same pattern as `SettingsLive.handle_event("scan", ...)`.
  def handle_event("scan", _params, socket) do
    {:noreply,
     socket
     |> assign(scanning: true)
     |> start_async(:scan, fn -> MediaCentaur.Watcher.Rescan.scan() end)}
  end

  # Result of the owned scan. A crash reaches the `{:exit, _}` clause, so
  # the "Scanning…" label always clears — a stuck label is the failure this
  # page had before (audit E52/DS17).
  @impl true
  def handle_async(:scan, {:ok, {:ok, _count}}, socket) do
    {:noreply, assign(socket, scanning: false)}
  end

  def handle_async(:scan, {:exit, reason}, socket) do
    Log.warning(:library, "Library scan failed", reason: inspect(reason))
    {:noreply, assign(socket, scanning: false)}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:library_view_updated, :browse}, socket) do
    # The Browse projection refreshed; re-read everything from scratch.
    # The projection itself broadcasts coalesced events upstream, so we
    # do not need to debounce here.
    {:noreply,
     socket
     |> load_library()
     |> cache_visible_ids()
     |> reset_stream()}
  end

  def handle_info({:entity_progress_updated, %{entity_id: entity_id}}, socket) do
    # The title detail host keeps the open modal's progress fresh on
    # its own. Here we refresh just the affected card's progress
    # summary so the bar / completion overlay reflects the change.
    updated_summaries = Library.ProgressRecords.summaries([entity_id])

    progress_by_id =
      case Map.get(updated_summaries, entity_id) do
        nil -> Map.delete(socket.assigns.progress_by_id, entity_id)
        summary -> Map.put(socket.assigns.progress_by_id, entity_id, summary)
      end

    {:noreply,
     socket
     |> assign(progress_by_id: progress_by_id)
     |> touch_stream_entries([entity_id])}
  end

  def handle_info({:playback_state_changed, %{entity_id: entity_id}}, socket) do
    # The title detail host owns the playing set. Here we only
    # re-render the affected poster card so the "playing" badge
    # appears/disappears.
    {:noreply, touch_stream_entries(socket, [entity_id])}
  end

  def handle_info({:playback_failed, %{payload: payload}}, socket) do
    {:noreply, put_flash(socket, :error, playback_failed_flash(payload))}
  end

  def handle_info({:config_updated, :media_dirs, _entries}, socket) do
    {:noreply,
     assign(socket,
       media_dirs: Config.get(:media_dirs) || [],
       media_dirs_configured: media_dirs_configured?()
     )}
  end

  # `LibraryCardInfoAware` / `CardPlayButtonAware` have already updated
  # their assigns via `attach_hook`; we reset the grid stream so existing
  # card items re-render with the new attr (stream items are not part
  # of subsequent diffs — they only re-render when the stream is reset).
  def handle_info({:setting_changed, key, _value}, socket)
      when key in ["library_show_card_info", "card_play_button"] do
    {:noreply, stream(socket, :grid, socket.assigns.entries, reset: true)}
  end

  # The empty state shows "Ingesting N files…" while the pipeline drains;
  # Pipeline.Stats broadcasts (coalesced) whenever that picture changes.
  def handle_info({:pipeline_stats_updated, :content}, socket) do
    snapshot = Stats.get_snapshot()
    depth = snapshot.discovery_queue_depth + snapshot.import_queue_depth
    {:noreply, assign(socket, pipeline_queue_depth: depth)}
  end

  def handle_info({:pipeline_stats_updated, :image}, socket), do: {:noreply, socket}

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    offline_summary = offline_summary(assigns.dir_status, assigns.unavailable_count)

    assigns = assign(assigns, :offline_summary, offline_summary)

    ~H"""
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/library"
      full_width
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <ReviewModal.review_modal
          subject={@review_subject}
          poster_url={@review_poster_url}
          sentiment={@review_sentiment}
          relay_counts={@review_relay_counts}
        />
      </:overlays>
      <div
        class="relative"
        data-page-behavior="library"
        data-nav-default-zone="library"
        data-nav-transient-params="title,entity,view,activity"
      >
        <%!-- Same fixed dark scrim the home page uses (left-weighted + a
              vertical dim that holds down the page) so the library reads as a
              rich dark surface rather than flat grey. It sits behind the grid
              (z-0), so it darkens the background, never the posters. Browse is
              its own subject — the page carries no artwork of its own. --%>
        <div class="page-side-dim" aria-hidden="true"></div>

        <div class="relative z-[1]">
          <.page_header title="Library" class="mb-5">
            <:subtitle>
              {count_label(@counts.movies, "movie")} · {count_label(@counts.tv, "show")}
            </:subtitle>
          </.page_header>

          <%!-- Storage offline banner --%>
          <LibraryCards.storage_offline_banner :if={@offline_summary} summary={@offline_summary} />

          <%!-- Library Browse zone --%>
          <section id="browse">
            <LibraryCards.toolbar
              active_tab={@active_tab}
              sort_order={@sort_order}
              sort_open={@sort_open}
              filter_text={@filter_text}
            />

            <%!-- Genuinely-empty library. The three reasons take three
                  actions, so the copy names which one applies rather than
                  stating a cause the page has not diagnosed. --%>
            <.empty_state
              :if={
                empty_grid_reason(@grid_count, @counts.all) == :library_empty and
                  not @media_dirs_configured
              }
              icon="hero-film"
              headline="Point it at your media"
            >
              Media Centaur scans the directories you name here and identifies what it finds.
              <:action>
                <.button
                  variant="primary"
                  size="sm"
                  navigate={~p"/settings?section=library"}
                  data-nav-item
                >
                  Add a media directory
                </.button>
              </:action>
            </.empty_state>

            <.empty_state
              :if={
                empty_grid_reason(@grid_count, @counts.all) == :library_empty and
                  @media_dirs_configured and @pipeline_queue_depth > 0
              }
              icon="hero-arrow-down-on-square-stack"
              headline="Importing your media"
            >
              {@pipeline_queue_depth} file{if @pipeline_queue_depth == 1, do: "", else: "s"} to go.
              Titles appear here as they are identified.
            </.empty_state>

            <.empty_state
              :if={
                empty_grid_reason(@grid_count, @counts.all) == :library_empty and
                  @media_dirs_configured and @pipeline_queue_depth == 0
              }
              icon="hero-film"
              headline="Nothing imported yet"
            >
              Your media directories are set, but no video files have been imported from them.
              <:action>
                <.button
                  variant="primary"
                  size="sm"
                  phx-click="scan"
                  disabled={@scanning}
                  data-nav-item
                >
                  {if @scanning, do: "Scanning…", else: "Scan media directories"}
                </.button>
              </:action>
            </.empty_state>

            <%!-- Library has entries but the active filter hid them all:
                  offer to clear the filter, never to scan. --%>
            <.empty_state
              :if={empty_grid_reason(@grid_count, @counts.all) == :no_matches}
              headline={no_matches_label(@filter_text)}
            >
              <:action>
                <.button variant="dismiss" size="sm" phx-click="reset_filters" data-nav-item>
                  Clear filters
                </.button>
              </:action>
            </.empty_state>

            <div :if={@grid_count > 0} data-nav-zone="grid" class="mt-4">
              <div
                id="library-grid"
                phx-update="stream"
                class="poster-grid poster-grid-dense"
                data-nav-grid
              >
                <LibraryCards.poster_card
                  :for={{dom_id, entry} <- @streams.grid}
                  id={dom_id}
                  entry={entry}
                  progress={Map.get(@progress_by_id, entry.id)}
                  selected={open_container_id(@title_detail) == entry.id}
                  playing={playing?(@title_playback, entry.id)}
                  show_info={@show_card_info}
                  show_play_button={@show_play_button}
                />
              </div>
            </div>
          </section>
        </div>

        <%!-- Detail modal (always in DOM for smooth backdrop-filter) --%>
        <DetailPanel.detail_panel
          detail={@title_detail}
          state={@modal_state}
          today={@today}
          review?={@show_discovery}
          spoiler_free={@spoiler_free}
          letterboxd_links={@letterboxd_links}
          tmdb_ready={@tmdb_ready}
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Data Loading ---

  # First-render data load — gated by `connected?` so the static HTTP
  # render ships empty defaults and the WebSocket render fills them in
  # once. See AGENTS.md → LiveView callbacks (Iron Law).
  # Loads on BOTH the disconnected (static) render and the connected
  # render — deliberately NOT gated on `connected?/1`. This is a desktop
  # app (UIDR-012): the first paint must already carry real data, never the
  # 0-count / empty-grid mount placeholders that would otherwise flash
  # before the socket connects. The read is cheap (a `Library.Views.browse`
  # ETS lookup plus a bounded set of local SQLite queries), so building it
  # once more on the static render is the right trade. Do not re-add a
  # `connected?` gate "to avoid the double load" — that reintroduces the
  # flash.
  defp ensure_loaded(socket) do
    if socket.assigns.loaded? do
      socket
    else
      socket
      |> load_library()
      |> assign(loaded?: true)
    end
  end

  defp load_library(socket) do
    entries = Library.Views.browse()
    ids = Enum.map(entries, & &1.id)
    progress_by_id = Library.ProgressRecords.summaries(ids)

    assign(socket,
      entries: entries,
      progress_by_id: progress_by_id,
      dir_status: MediaFileAvailability.dir_status(),
      unavailable_count: Enum.count(entries, &(not &1.available?)),
      counts: tab_counts(entries),
      playback: load_playback_sessions()
    )
  end

  # --- Stream Management ---

  defp reset_stream(socket) do
    filtered = compute_filtered(socket)

    socket
    |> stream(:grid, filtered, reset: true)
    |> assign(grid_count: length(filtered))
  end

  defp touch_stream_entries(socket, entity_ids) do
    filtered_ids = socket.assigns.visible_ids
    by_id = entries_index(socket.assigns.entries)

    Enum.reduce(entity_ids, socket, fn id, sock ->
      entry = Map.get(by_id, id)

      cond do
        entry == nil ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")

        MapSet.member?(filtered_ids, id) ->
          stream_insert(sock, :grid, entry)

        true ->
          stream_delete_by_dom_id(sock, :grid, "entity-#{id}")
      end
    end)
  end

  defp entries_index(entries), do: Map.new(entries, &{&1.id, &1})

  defp compute_filtered(socket) do
    assigns = socket.assigns

    assigns.entries
    |> filtered_by_tab(assigns.active_tab)
    |> filtered_by_text(assigns.filter_text)
    |> sorted_by(assigns.sort_order, assigns.progress_by_id)
  end

  # Caches the filtered visible-ID set so subsequent
  # `touch_stream_entries` calls (one per PubSub event burst) read O(1)
  # from assigns instead of rescanning `entries`. Invalidate by calling
  # this whenever `entries` or any filter assign (active_tab,
  # filter_text) changes.
  defp cache_visible_ids(socket) do
    assigns = socket.assigns

    visible_ids =
      assigns.entries
      |> filtered_by_tab(assigns.active_tab)
      |> filtered_by_text(assigns.filter_text)
      |> MapSet.new(& &1.id)

    assign(socket, visible_ids: visible_ids)
  end

  # --- URL Params ---

  defp parse_tab("movies"), do: :movies
  defp parse_tab("tv"), do: :tv
  defp parse_tab(_), do: :all

  # The sort values the URL may carry, in the menu's order —
  # `LibraryCards.@sort_options` renders the same list with its labels.
  @sort_options [:recent, :watched, :alpha, :year]

  defp parse_sort(sort), do: Enum.find(@sort_options, :recent, &(Atom.to_string(&1) == sort))

  # --- TitleDetailHost ---

  # This page holds no snapshot of its own: every title it opens is one
  # the library owns, and the host reads it by identity.
  @impl TitleDetailHost
  def page_facts(_socket, _ref, _params), do: {nil, %{}}

  # The modal's query over the page's own params, so opening or closing
  # a title never loses the tab, sort or filter.
  @impl TitleDetailHost
  def title_detail_path(socket, query), do: build_path(socket, %{}, query)

  @impl TitleDetailHost
  def open_plan_board(socket, plan_id), do: push_navigate(socket, to: ~p"/incoming?plan=#{plan_id}")

  # Build a URL path preserving current socket state with overrides.
  # Page-level params here; the modal's own query comes whole from the
  # host (`TitleDetailHost.modal_query/1`) so it can't drift per host.
  defp build_path(socket, overrides, modal_query \\ nil) do
    assigns = socket.assigns

    tab = Map.get(overrides, :tab, assigns.active_tab)
    sort = Map.get(overrides, :sort, assigns.sort_order)
    filter = Map.get(overrides, :filter, assigns.filter_text)

    params =
      Enum.reject(
        [
          tab: if(tab != :all, do: tab),
          sort: if(sort != :recent, do: sort),
          filter: if(filter != "", do: filter)
        ],
        fn {_key, value} -> is_nil(value) end
      ) ++ (modal_query || TitleDetailHost.modal_query(socket))

    if params == [], do: ~p"/library", else: ~p"/library?#{params}"
  end

  # --- Helpers ---

  defp playing?(playback, entity_id), do: Map.has_key?(playback, entity_id)

  # The grid's lit card: the open modal's container (a collection's card
  # while one of its members is the subject).
  defp open_container_id(nil), do: nil
  defp open_container_id(detail), do: TitleDetailHost.LibraryHalf.container_id(detail)
end
