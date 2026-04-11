defmodule MediaCentaurWeb.WatchHistoryLive do
  @moduledoc """
  Watch history page — stats bar, GitHub-style heatmap, and a filterable
  completion event list with real-time updates and mark-as-unwatched.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Format, WatchHistory}
  alias MediaCentaur.WatchHistory.Stats

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: WatchHistory.subscribe()

    stats = WatchHistory.stats()
    events = WatchHistory.list_events()

    {:ok,
     assign(socket,
       stats: stats,
       heatmap_cells: Stats.heatmap_cells(stats.heatmap),
       events: events,
       filter_type: nil,
       filter_search: "",
       filter_date: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/history">
      <div class="max-w-5xl mx-auto space-y-8 py-6" data-page-behavior="watch-history">
        <h1 class="text-2xl font-bold">Watch History</h1>

        <%!-- Stats bar --%>
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-title">Titles Completed</div>
            <div class="stat-value">{@stats.total_count}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Hours Watched</div>
            <div class="stat-value">{format_hours(@stats.total_seconds)}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Current Streak</div>
            <div class="stat-value">{@stats.streak}d</div>
            <div class="stat-desc">
              {if @stats.streak == 0, do: "No active streak", else: "consecutive days"}
            </div>
          </div>
        </div>

        <%!-- Heatmap --%>
        <div class="bg-base-200 rounded-box p-4 overflow-x-auto">
          <h2 class="text-sm font-medium text-base-content/60 mb-3">Completions — last 52 weeks</h2>
          <svg
            width="676"
            height="91"
            viewBox="0 0 676 91"
            xmlns="http://www.w3.org/2000/svg"
          >
            <rect
              :for={cell <- @heatmap_cells}
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

        <%!-- Filters --%>
        <div class="flex flex-wrap items-center gap-3">
          <div role="group" class="join">
            <button
              class={["join-item btn btn-sm", is_nil(@filter_type) && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="all"
            >
              All
            </button>
            <button
              class={["join-item btn btn-sm", @filter_type == :movie && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="movie"
            >
              Movies
            </button>
            <button
              class={["join-item btn btn-sm", @filter_type == :episode && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="episode"
            >
              Episodes
            </button>
            <button
              class={["join-item btn btn-sm", @filter_type == :video_object && "btn-active"]}
              phx-click="filter_type"
              phx-value-type="video_object"
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
            class="btn btn-sm btn-ghost"
            phx-click="clear_date_filter"
          >
            {Date.to_string(@filter_date)} ×
          </button>
        </div>

        <%!-- Event list --%>
        <div class="space-y-2">
          <div
            :if={@events == []}
            class="text-base-content/50 py-12 text-center"
          >
            No completions yet.
          </div>

          <div
            :for={event <- @events}
            class="flex items-center gap-4 p-3 rounded-box bg-base-200 group"
          >
            <div class="w-10 h-14 flex-shrink-0 rounded overflow-hidden bg-base-300">
              <img
                :if={event_poster_url(event)}
                src={event_poster_url(event)}
                class="w-full h-full object-cover"
                alt=""
              />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{event.title}</div>
              <div class="text-sm text-base-content/60">
                <span class="badge badge-ghost badge-sm mr-2">{type_label(event.entity_type)}</span>
                Completed {format_completed_at(event.completed_at)} · {Format.format_seconds(
                  round(event.duration_seconds)
                )}
              </div>
            </div>
            <button
              class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100 transition-opacity"
              phx-click="delete_event"
              phx-value-id={event.id}
              data-confirm="Mark as unwatched? This will reset your progress."
            >
              Unwatch
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

    events = load_events(socket, entity_type: type)
    {:noreply, assign(socket, events: events, filter_type: type)}
  end

  @impl true
  def handle_event("filter_search", %{"value" => search}, socket) do
    events = load_events(socket, search: search)
    {:noreply, assign(socket, events: events, filter_search: search)}
  end

  @impl true
  def handle_event("filter_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        events = load_events(socket, date: date)
        {:noreply, assign(socket, events: events, filter_date: date)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    events = load_events(socket, date: nil)
    {:noreply, assign(socket, events: events, filter_date: nil)}
  end

  @impl true
  def handle_event("delete_event", %{"id" => id}, socket) do
    case WatchHistory.get_event(id) do
      nil ->
        {:noreply, socket}

      event ->
        WatchHistory.delete_event!(event)
        stats = WatchHistory.stats()
        events = load_events(socket)

        {:noreply,
         assign(socket,
           events: events,
           stats: stats,
           heatmap_cells: Stats.heatmap_cells(stats.heatmap)
         )}
    end
  end

  @impl true
  def handle_info({:watch_event_created, _event}, socket) do
    stats = WatchHistory.stats()
    events = load_events(socket)

    {:noreply,
     assign(socket,
       events: events,
       stats: stats,
       heatmap_cells: Stats.heatmap_cells(stats.heatmap)
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  defp load_events(socket, overrides \\ []) do
    opts =
      [
        entity_type: socket.assigns.filter_type,
        search: socket.assigns.filter_search,
        date: socket.assigns.filter_date
      ]
      |> Keyword.merge(overrides)

    WatchHistory.list_events(opts)
  end

  def heatmap_fill(0), do: "fill: oklch(var(--b3))"
  def heatmap_fill(1), do: "fill: oklch(var(--su) / 0.35)"
  def heatmap_fill(n) when n <= 3, do: "fill: oklch(var(--su) / 0.65)"
  def heatmap_fill(_), do: "fill: oklch(var(--su))"

  def heatmap_tooltip(%{count: 0, date: date}), do: Date.to_string(date)
  def heatmap_tooltip(%{count: 1, date: date}), do: "#{Date.to_string(date)} — 1 completion"
  def heatmap_tooltip(%{count: n, date: date}), do: "#{Date.to_string(date)} — #{n} completions"

  def type_label(:movie), do: "Movie"
  def type_label(:episode), do: "Episode"
  def type_label(:video_object), do: "Video"

  def format_hours(seconds) do
    hours = round(seconds / 3600)
    "#{hours} hrs"
  end

  def format_completed_at(completed_at) do
    Calendar.strftime(completed_at, "%B %-d, %Y at %-I:%M %p")
  end

  @doc """
  Returns the poster image URL for a watch event, or nil if unavailable.
  Resolves the first non-nil entity association (movie, episode, video_object).
  """
  def event_poster_url(event) do
    entity = event.movie || event.episode || event.video_object
    if entity, do: image_url(entity, "poster")
  end
end
