defmodule MediaCentaurWeb.WatchHistoryLive do
  @moduledoc """
  Watch history page — stats bar, GitHub-style heatmap, and a filterable
  watch event list with real-time updates.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Views, as: WatchHistoryViews
  alias MediaCentaurWeb.LibraryFormatters

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Source topic — drives the paginated events-list refresh.
      WatchHistory.subscribe()
      # Derived topic — drives the aggregate panel refresh (stats,
      # heatmap, rewatch counts) via the projection (ADR-041).
      WatchHistoryViews.subscribe()
    end

    socket =
      assign(socket,
        loaded?: false,
        stats: %{total_count: 0, total_seconds: 0.0, streak: 0},
        heatmap_cells_by_type: %{nil => [], movie: [], episode: [], video_object: []},
        rewatch_counts: %{movie: %{}, episode: %{}, video_object: %{}},
        filter_type: nil,
        filter_search: "",
        filter_date: nil,
        page: 1,
        events: [],
        has_next: false,
        deleting_event: nil,
        deleted_event: nil,
        reload_timer: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, ensure_loaded(socket)}
  end

  # First-render data load — gated by `connected?` so the static HTTP render
  # ships empty defaults and the WebSocket render fills them in once. See
  # AGENTS.md → LiveView callbacks (Iron Law).
  #
  # Per the "no blocking LV page loads" rule, the summary read + first
  # page of events run on a supervised task and message back via
  # `{:history_loaded, _}`. The summary is a microsecond ETS read but
  # `fetch_page/1` is a paginated DB query that scales with the history
  # table; deferring it keeps `handle_params` snappy on big histories.
  defp ensure_loaded(socket) do
    if socket.assigns.loaded? do
      socket
    else
      socket
      |> load_history()
      |> assign(:loaded?, true)
    end
  end

  # Synchronous first-render load. The summary is a microsecond ETS read
  # and `fetch_page_for/1` is a single paginated local query — running
  # them inline on both the disconnected and connected renders keeps the
  # first paint correct (no empty-state flash) at negligible local cost.
  # Desktop first-paint correctness (see AGENTS.md → LiveView callbacks).
  defp load_history(socket) do
    summary = WatchHistoryViews.summary()
    {events, has_next} = fetch_page_for(filter_snapshot(socket))

    assign(socket,
      stats: summary.stats,
      heatmap_cells_by_type: summary.heatmap_cells_by_type,
      rewatch_counts: summary.rewatch_counts,
      events: events,
      has_next: has_next
    )
  end

  defp filter_snapshot(socket) do
    %{
      page: socket.assigns.page,
      filter_type: socket.assigns.filter_type,
      filter_search: socket.assigns.filter_search,
      filter_date: socket.assigns.filter_date
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/history"
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <:overlays>
        <%!-- Deleting in-progress modal — persistent (no casual dismissal while
              the delete is running). --%>
        <.modal
          id="history-deleting-modal"
          open={!is_nil(@deleting_event)}
          dismiss={:persistent}
          size={:sm}
          panel_class="p-6 flex flex-col items-center gap-4"
        >
          <span class="loading loading-spinner loading-md text-base-content/50"></span>
          <div class="text-center">
            <p class="text-sm font-medium text-base-content/70">Removing from history…</p>
            <p class="text-xs text-base-content/40 mt-1 truncate max-w-xs">
              {@deleting_event && @deleting_event.title}
            </p>
          </div>
        </.modal>

        <%!-- Deleted summary modal — ephemeral. --%>
        <.modal
          id="history-deleted-modal"
          open={!is_nil(@deleted_event)}
          dismiss={:ephemeral}
          on_close="dismiss_deleted_event"
          size={:sm}
          panel_class="p-6 space-y-4"
        >
          <div :if={@deleted_event}>
            <div class="flex items-start gap-3">
              <div class="rounded-full bg-error/10 p-2 shrink-0">
                <.icon name="hero-trash-mini" class="size-4 text-error" />
              </div>
              <div class="min-w-0">
                <h3 class="font-semibold">Removed from history</h3>
                <p class="text-sm text-base-content/60 truncate mt-0.5">
                  {@deleted_event && @deleted_event.title}
                </p>
                <p class="text-xs text-base-content/40 mt-1">
                  {@deleted_event && type_label(@deleted_event.entity_type)}
                </p>
              </div>
            </div>
            <div class="flex justify-end">
              <.button variant="dismiss" size="sm" phx-click="dismiss_deleted_event">
                Close
              </.button>
            </div>
          </div>
        </.modal>
      </:overlays>
      <div
        class="max-w-5xl mx-auto space-y-6 py-6"
        data-page-behavior="watch-history"
        data-nav-default-zone="watch_history"
      >
        <h1 class="text-2xl font-bold">Watch History</h1>

        <%!-- Stats --%>
        <div class="grid grid-cols-3 gap-4">
          <div class="glass-inset rounded-xl px-5 py-4">
            <div class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-1">
              Titles Watched
            </div>
            <div class="text-3xl font-bold tabular-nums">{@stats.total_count}</div>
          </div>
          <div class="glass-inset rounded-xl px-5 py-4">
            <div class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-1">
              Hours Watched
            </div>
            <div class="text-3xl font-bold tabular-nums">{format_hours(@stats.total_seconds)}</div>
          </div>
          <div class="glass-inset rounded-xl px-5 py-4">
            <div class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-1">
              Current Streak
            </div>
            <div class="text-3xl font-bold tabular-nums">
              {@stats.streak}<span class="text-base font-normal text-base-content/50 ml-0.5">d</span>
            </div>
            <div class="text-xs text-base-content/40 mt-1">
              {if @stats.streak == 0, do: "no active streak", else: "consecutive days"}
            </div>
          </div>
        </div>

        <%!-- Heatmap — only the ACTIVE type variant renders. Pre-rendering all
              four variants put ~1,460 <rect>s in every /history navigation
              payload (~276KB, the heaviest page in the app) to save a server
              swap the type filter performs anyway for the events list
              (campaigns/instant-navigation.md Phase 2). --%>
        <div class="glass-inset rounded-xl p-4 overflow-x-auto w-fit">
          <div data-heatmap={heatmap_key(@filter_type)}>
            <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-3">
              {heatmap_title(@filter_type)} — last 52 weeks
            </h2>
            <svg width="676" height="91" viewBox="0 0 676 91" xmlns="http://www.w3.org/2000/svg">
              <%!-- Zero-count cells carry no tooltip/click attrs — on an
                    empty year that's ~40KB of dead payload per navigation. --%>
              <rect
                :for={cell <- @heatmap_cells_by_type[@filter_type]}
                x={cell.x}
                y={cell.y}
                width="11"
                height="11"
                rx="2"
                class={[heatmap_class(cell.count), cell.count > 0 && "cursor-pointer"]}
                phx-click={if cell.count > 0, do: "filter_date"}
                phx-value-date={if cell.count > 0, do: Date.to_iso8601(cell.date)}
              >
                <title :if={cell.count > 0}>{heatmap_tooltip(cell)}</title>
              </rect>
            </svg>
          </div>
        </div>

        <%!-- Filters --%>
        <div data-nav-zone="toolbar" class="flex flex-wrap items-center gap-3">
          <div role="group" class="join">
            <button
              :for={
                {type, value, label} <- [
                  {nil, "all", "All"},
                  {:movie, "movie", "Movies"},
                  {:episode, "episode", "Episodes"},
                  {:video_object, "video_object", "Video"}
                ]
              }
              class={["join-item btn btn-sm", @filter_type == type && "btn-active"]}
              data-nav-item
              tabindex="0"
              phx-click="filter_type"
              phx-value-type={value}
            >
              {label}
            </button>
          </div>

          <input
            type="search"
            class="input input-bordered input-sm"
            placeholder="Search titles…"
            value={@filter_search}
            phx-change="filter_search"
            phx-debounce="300"
            name="value"
            data-nav-item
            data-captures-keys
            tabindex="0"
          />

          <.button
            :if={@filter_date}
            variant="primary"
            size="xs"
            class="gap-1"
            data-nav-item
            tabindex="0"
            phx-click="clear_date_filter"
          >
            {Calendar.strftime(@filter_date, "%b %-d, %Y")}
            <.icon name="hero-x-mark-mini" class="size-3" />
          </.button>
        </div>

        <%!-- Event list --%>
        <p :if={@events == []} class="text-center text-base-content/40 py-16">
          Nothing watched yet.
        </p>

        <div
          :if={@events != []}
          data-nav-zone="grid"
          class="glass-inset rounded-xl overflow-hidden"
        >
          <div
            :for={event <- @events}
            class="flex items-baseline gap-4 px-4 py-2.5 group hover:bg-base-content/5 focus-within:bg-base-content/5 border-b border-base-content/5 last:border-0"
            data-nav-item
            tabindex="0"
          >
            <span class="flex-1 min-w-0 flex items-baseline gap-2 min-w-0">
              <span class="text-sm font-medium truncate">{event.title}</span>
              <.badge
                :if={rewatch_count_for_event(event, @rewatch_counts) >= 2}
                variant="soft_primary"
                class="text-xs shrink-0"
              >
                {rewatch_count_for_event(event, @rewatch_counts)}×
              </.badge>
            </span>
            <span class="text-xs text-base-content/50 whitespace-nowrap shrink-0">
              {type_label(event.entity_type)}
            </span>
            <span class="text-xs text-base-content/40 whitespace-nowrap shrink-0">
              {format_completed_at(event.completed_at)}
            </span>
            <%!-- `Xh Ym`, the app-wide duration vocabulary (UIDR-004). The
                  clock-style `Format.format_seconds/1` belongs to player
                  overlays, where a scrub position is the point. --%>
            <span class="text-xs text-base-content/40 whitespace-nowrap shrink-0 tabular-nums w-16 text-right">
              {LibraryFormatters.format_human_duration(round(event.duration_seconds))}
            </span>
            <.button
              variant="destructive_inline"
              size="xs"
              class="text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity"
              phx-click="remove_event"
              phx-value-id={event.id}
              tabindex="0"
              aria-label="Remove from history"
            >
              <.icon name="hero-x-mark-mini" class="size-3" />
            </.button>
          </div>
        </div>

        <%!-- Pagination — lives inside the grid zone so UP from here reaches the toolbar --%>
        <div
          :if={@page > 1 || @has_next}
          data-nav-zone="grid"
          class="flex items-center justify-center gap-4 py-2"
        >
          <.button
            :if={@page > 1}
            variant="dismiss"
            size="sm"
            data-nav-item
            tabindex="0"
            phx-click="prev_page"
          >
            ← Previous
          </.button>
          <span class="text-sm text-base-content/40">Page {@page}</span>
          <.button
            :if={@has_next}
            variant="dismiss"
            size="sm"
            data-nav-item
            tabindex="0"
            phx-click="next_page"
          >
            Next →
          </.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter_type", %{"type" => type_str}, socket) do
    type =
      case type_str do
        "movie" -> :movie
        "episode" -> :episode
        "video_object" -> :video_object
        _ -> nil
      end

    socket = assign(socket, filter_type: type, page: 1)
    {events, has_next} = fetch_page(socket)
    {:noreply, assign(socket, events: events, has_next: has_next)}
  end

  @impl true
  def handle_event("filter_search", %{"value" => search}, socket) do
    socket = assign(socket, filter_search: search, page: 1)
    {events, has_next} = fetch_page(socket)
    {:noreply, assign(socket, events: events, has_next: has_next)}
  end

  @impl true
  def handle_event("filter_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        socket = assign(socket, filter_date: date, page: 1)
        {events, has_next} = fetch_page(socket)
        {:noreply, assign(socket, events: events, has_next: has_next)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    socket = assign(socket, filter_date: nil, page: 1)
    {events, has_next} = fetch_page(socket)
    {:noreply, assign(socket, events: events, has_next: has_next)}
  end

  @impl true
  def handle_event("remove_event", %{"id" => id}, socket) do
    case WatchHistory.get_event(id) do
      nil ->
        {:noreply, socket}

      event ->
        # `delete_event!` is a local sqlite delete + PubSub broadcast —
        # fast enough to run synchronously (ADR-044), and a delete must
        # complete regardless of navigation (no cancel-on-leave). The
        # aggregate refresh (stats / heatmap / rewatch counts) arrives via
        # the `WatchHistory.Views.Summary` projection, which observes the
        # `:watch_event_deleted` broadcast and re-emits
        # `{:watch_history_view_updated, :summary}` on the derived topic.
        WatchHistory.delete_event!(event)

        socket = assign(socket, page: 1, deleted_event: event, deleting_event: nil)
        {events, has_next} = fetch_page(socket)
        {:noreply, assign(socket, events: events, has_next: has_next)}
    end
  end

  @impl true
  def handle_event("dismiss_deleted_event", _params, socket) do
    {:noreply, assign(socket, deleted_event: nil)}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    socket = assign(socket, page: max(1, socket.assigns.page - 1))
    {events, has_next} = fetch_page(socket)
    {:noreply, assign(socket, events: events, has_next: has_next)}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    socket = assign(socket, page: socket.assigns.page + 1)
    {events, has_next} = fetch_page(socket)
    {:noreply, assign(socket, events: events, has_next: has_next)}
  end

  @impl true
  def handle_info({:watch_event_created, _event}, socket) do
    # Source event — the projection observes this too and will emit
    # `:watch_history_view_updated` after its refresh. Here we only
    # care about reloading the paginated events list itself.
    {:noreply, debounce(socket, :reload_timer, :reload_history, 500)}
  end

  def handle_info({:watch_event_deleted, _event}, socket) do
    # Local list was already pruned in `handle_event("remove_event", …)`;
    # nothing more to do here. Aggregates refresh via the derived topic.
    {:noreply, socket}
  end

  def handle_info({:watch_history_view_updated, :summary}, socket) do
    # Derived event — projection finished its refresh, pull the new
    # snapshot in one read (ADR-041 encapsulation rule: consumers
    # subscribe to derived topics, not source events for aggregates).
    summary = WatchHistoryViews.summary()

    {:noreply,
     assign(socket,
       stats: summary.stats,
       heatmap_cells_by_type: summary.heatmap_cells_by_type,
       rewatch_counts: summary.rewatch_counts
     )}
  end

  def handle_info(:reload_history, socket) do
    socket = assign(socket, page: 1)
    {events, has_next} = fetch_page(socket)
    {:noreply, assign(socket, events: events, has_next: has_next)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  @doc """
  Refresh `current` rewatch-count map for only the given `types`. Other
  entries are left untouched. `fetch_fn` is the per-type fetcher (defaults
  to `WatchHistory.rewatch_count_map/1`); accepting it lets unit tests
  inject a spy.
  """
  @spec update_rewatch_counts(map(), Enumerable.t(), (atom() -> map())) :: map()
  def update_rewatch_counts(current, types, fetch_fn \\ &WatchHistory.rewatch_count_map/1) do
    Enum.reduce(types, current, fn type, acc ->
      Map.put(acc, type, fetch_fn.(type))
    end)
  end

  defp rewatch_count_for_event(event, rewatch_counts) do
    case event.entity_type do
      :movie -> Map.get(rewatch_counts.movie, event.movie_id, 0)
      :episode -> Map.get(rewatch_counts.episode, event.episode_id, 0)
      :video_object -> Map.get(rewatch_counts.video_object, event.video_object_id, 0)
      _ -> 0
    end
  end

  defp fetch_page(socket), do: fetch_page_for(filter_snapshot(socket))

  defp fetch_page_for(%{} = filters) do
    offset = (filters.page - 1) * @page_size

    raw =
      WatchHistory.list_events(
        entity_type: filters.filter_type,
        search: filters.filter_search,
        date: filters.filter_date,
        limit: @page_size + 1,
        offset: offset
      )

    has_next = length(raw) > @page_size
    events = Enum.take(raw, @page_size)
    {events, has_next}
  end

  def heatmap_key(nil), do: "all"
  def heatmap_key(type), do: Atom.to_string(type)

  def heatmap_title(nil), do: "All Watched"
  def heatmap_title(:movie), do: "Movies Watched"
  def heatmap_title(:episode), do: "Episodes Watched"
  def heatmap_title(:video_object), do: "Videos Watched"

  # Fill intensity as CSS classes (`.hm-fill-*` in app.css) rather than
  # inline color-mix style strings — the ~70-char style on each of 365
  # rects tripled the heatmap's payload share.
  def heatmap_class(0), do: "hm-fill-0"
  def heatmap_class(1), do: "hm-fill-1"
  def heatmap_class(n) when n <= 3, do: "hm-fill-2"
  def heatmap_class(_), do: "hm-fill-3"

  def heatmap_tooltip(%{count: 0, date: date}), do: Date.to_string(date)
  def heatmap_tooltip(%{count: 1, date: date}), do: "#{Date.to_string(date)} — 1 watched"
  def heatmap_tooltip(%{count: n, date: date}), do: "#{Date.to_string(date)} — #{n} watched"

  def type_label(:movie), do: "Movie"
  def type_label(:episode), do: "Episode"
  def type_label(:video_object), do: "Video"

  def format_hours(seconds) do
    hours = round(seconds / 3600)
    "#{hours} hrs"
  end

  def format_completed_at(completed_at) do
    Calendar.strftime(completed_at, "%b %-d, %Y")
  end
end
