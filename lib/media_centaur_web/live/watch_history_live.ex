defmodule MediaCentaurWeb.WatchHistoryLive do
  @moduledoc """
  Watch history page — stats bar, GitHub-style heatmap, and a filterable
  watch event list with real-time updates.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Format, WatchHistory}

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: WatchHistory.subscribe()

    stats = WatchHistory.stats()
    heatmap_cells_by_type = WatchHistory.heatmap_cells_by_type()

    socket =
      assign(socket,
        stats: stats,
        heatmap_cells_by_type: heatmap_cells_by_type,
        filter_type: nil,
        filter_search: "",
        filter_date: nil,
        page: 1,
        deleting_event: nil,
        deleted_event: nil,
        delete_task: nil
      )

    {events, has_next} = fetch_page(socket)

    {:ok, assign(socket, events: events, has_next: has_next)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/history">
      <div class="max-w-5xl mx-auto space-y-6 py-6" data-page-behavior="watch-history">
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

        <%!-- Heatmap — all 4 type variants pre-rendered; JS toggles the wrapper instantly --%>
        <div class="glass-inset rounded-xl p-4 overflow-x-auto w-fit">
          <div
            :for={
              {type, key, label} <- [
                {nil, "all", "All Watched"},
                {:movie, "movie", "Movies Watched"},
                {:episode, "episode", "Episodes Watched"},
                {:video_object, "video_object", "Videos Watched"}
              ]
            }
            data-heatmap={key}
            class={if @filter_type == type, do: "", else: "hidden"}
          >
            <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-3">
              {label} — last 52 weeks
            </h2>
            <svg width="676" height="91" viewBox="0 0 676 91" xmlns="http://www.w3.org/2000/svg">
              <rect
                :for={cell <- @heatmap_cells_by_type[type]}
                x={cell.x}
                y={cell.y}
                width="11"
                height="11"
                rx="2"
                style={heatmap_fill(cell.count)}
                class={if cell.count > 0, do: "cursor-pointer", else: "cursor-default"}
                phx-click={if cell.count > 0, do: "filter_date"}
                phx-value-date={Date.to_iso8601(cell.date)}
              >
                <title>{heatmap_tooltip(cell)}</title>
              </rect>
            </svg>
          </div>
        </div>

        <%!-- Filters --%>
        <div class="flex flex-wrap items-center gap-3">
          <div role="group" class="join">
            <button
              class={["join-item btn btn-sm", is_nil(@filter_type) && "btn-active"]}
              phx-click={
                JS.hide(to: "[data-heatmap]")
                |> JS.show(to: "[data-heatmap='all']")
                |> JS.push("filter_type", value: %{type: "all"})
              }
            >
              All
            </button>
            <button
              class={["join-item btn btn-sm", @filter_type == :movie && "btn-active"]}
              phx-click={
                JS.hide(to: "[data-heatmap]")
                |> JS.show(to: "[data-heatmap='movie']")
                |> JS.push("filter_type", value: %{type: "movie"})
              }
            >
              Movies
            </button>
            <button
              class={["join-item btn btn-sm", @filter_type == :episode && "btn-active"]}
              phx-click={
                JS.hide(to: "[data-heatmap]")
                |> JS.show(to: "[data-heatmap='episode']")
                |> JS.push("filter_type", value: %{type: "episode"})
              }
            >
              Episodes
            </button>
            <button
              class={["join-item btn btn-sm", @filter_type == :video_object && "btn-active"]}
              phx-click={
                JS.hide(to: "[data-heatmap]")
                |> JS.show(to: "[data-heatmap='video_object']")
                |> JS.push("filter_type", value: %{type: "video_object"})
              }
            >
              Video
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
          />

          <button
            :if={@filter_date}
            class="badge badge-primary badge-sm gap-1 cursor-pointer py-3 px-2.5"
            phx-click="clear_date_filter"
          >
            {Calendar.strftime(@filter_date, "%b %-d, %Y")}
            <.icon name="hero-x-mark-mini" class="size-3" />
          </button>
        </div>

        <%!-- Event list --%>
        <p :if={@events == []} class="text-center text-base-content/40 py-16">
          Nothing watched yet.
        </p>

        <div :if={@events != []} class="glass-inset rounded-xl overflow-hidden">
          <div
            :for={event <- @events}
            class="flex items-baseline gap-4 px-4 py-2.5 group hover:bg-base-content/5 border-b border-base-content/5 last:border-0"
          >
            <span class="flex-1 min-w-0 text-sm font-medium truncate">{event.title}</span>
            <span class="text-xs text-base-content/50 whitespace-nowrap shrink-0">
              {type_label(event.entity_type)}
            </span>
            <span class="text-xs text-base-content/40 whitespace-nowrap shrink-0">
              {format_completed_at(event.completed_at)}
            </span>
            <span class="text-xs text-base-content/40 whitespace-nowrap shrink-0 tabular-nums w-14 text-right">
              {Format.format_seconds(round(event.duration_seconds))}
            </span>
            <button
              class="btn btn-ghost btn-xs text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
              phx-click="remove_event"
              phx-value-id={event.id}
            >
              <.icon name="hero-x-mark-mini" class="size-3" />
            </button>
          </div>
        </div>

        <%!-- Pagination --%>
        <div :if={@page > 1 || @has_next} class="flex items-center justify-center gap-4 py-2">
          <button
            :if={@page > 1}
            class="btn btn-ghost btn-sm"
            phx-click="prev_page"
          >
            ← Previous
          </button>
          <span class="text-sm text-base-content/40">Page {@page}</span>
          <button
            :if={@has_next}
            class="btn btn-ghost btn-sm"
            phx-click="next_page"
          >
            Next →
          </button>
        </div>
      </div>

      <%!-- Deleting in-progress modal --%>
      <div class="modal-backdrop" data-state={if @deleting_event, do: "open", else: "closed"}>
        <div class="modal-panel modal-panel-sm p-6 flex flex-col items-center gap-4">
          <span class="loading loading-spinner loading-md text-base-content/50"></span>
          <div class="text-center">
            <p class="text-sm font-medium text-base-content/70">Removing from history…</p>
            <p class="text-xs text-base-content/40 mt-1 truncate max-w-xs">
              {@deleting_event && @deleting_event.title}
            </p>
          </div>
        </div>
      </div>

      <%!-- Deleted summary modal --%>
      <div
        class="modal-backdrop"
        data-state={if @deleted_event, do: "open", else: "closed"}
        phx-click-away={@deleted_event && "dismiss_deleted_event"}
        phx-window-keydown={@deleted_event && "dismiss_deleted_event"}
        phx-key="Escape"
      >
        <div class="modal-panel modal-panel-sm p-6 space-y-4">
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
            <button class="btn btn-ghost btn-sm" phx-click="dismiss_deleted_event">
              Close
            </button>
          </div>
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
        task =
          Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, fn ->
            WatchHistory.remove_event!(event)

            %{
              stats: WatchHistory.stats(),
              heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type()
            }
          end)

        {:noreply, assign(socket, deleting_event: event, delete_task: task.ref)}
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
  def handle_info({ref, %{stats: stats, heatmap_cells_by_type: heatmap}}, socket)
      when socket.assigns.delete_task == ref do
    Process.demonitor(ref, [:flush])
    socket = assign(socket, page: 1)
    {events, has_next} = fetch_page(socket)

    {:noreply,
     assign(socket,
       events: events,
       has_next: has_next,
       stats: stats,
       heatmap_cells_by_type: heatmap,
       deleted_event: socket.assigns.deleting_event,
       deleting_event: nil,
       delete_task: nil
     )}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when socket.assigns.delete_task == ref do
    {:noreply, assign(socket, deleting_event: nil, delete_task: nil)}
  end

  @impl true
  def handle_info({:watch_event_created, _event}, socket) do
    stats = WatchHistory.stats()
    socket = assign(socket, page: 1)
    {events, has_next} = fetch_page(socket)

    {:noreply,
     assign(socket,
       events: events,
       has_next: has_next,
       stats: stats,
       heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type()
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  defp fetch_page(socket) do
    a = socket.assigns
    offset = (a.page - 1) * @page_size

    raw =
      WatchHistory.list_events(
        entity_type: a.filter_type,
        search: a.filter_search,
        date: a.filter_date,
        limit: @page_size + 1,
        offset: offset
      )

    has_next = length(raw) > @page_size
    events = Enum.take(raw, @page_size)
    {events, has_next}
  end

  def heatmap_fill(0), do: "fill: var(--color-base-300)"
  def heatmap_fill(1), do: "fill: color-mix(in oklch, var(--color-success) 30%, transparent)"

  def heatmap_fill(n) when n <= 3,
    do: "fill: color-mix(in oklch, var(--color-success) 60%, transparent)"

  def heatmap_fill(_), do: "fill: var(--color-success)"

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
