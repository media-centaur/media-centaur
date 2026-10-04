defmodule MediaCentaurWeb.ConsolePageLive do
  @moduledoc """
  Full-page `/console` route — the diagnostic firehose: every component's
  log ring, filtered by component chips and a level floor, with clear,
  resize, copy and download. The rows are a `log_view/1`: oldest at the top,
  new lines appended at the bottom, following or held in the browser. The
  text search is the browser's: the `ConsolePage` hook hides non-matching
  rows, keeps the query across reloads, and sends it with copy and download.

  It renders in the app shell with Status marked active — it has no
  sidebar entry of its own. Each Status drill-in's log preview links it, as
  `/console?subsystem=<name>`: a scoped visit whose filter is that
  subsystem's (`HealthBoard.log_filter/1`) and belongs to this view alone —
  chip and level edits change it without touching the saved filter, and
  saved-filter changes made elsewhere do not reach it. Unscoped, the filter
  is the saved one in `MediaCentaur.Console.Buffer`, edited through it and
  kept in sync over PubSub.

  Pure decision logic (scope, filter mutation, payload formatting) lives in
  `MediaCentaurWeb.ConsolePageLive.Logic` (ADR-030).
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Console
  alias MediaCentaur.Console.{Buffer, Filter, View}
  alias MediaCentaurWeb.ConsolePageLive.Logic
  alias MediaCentaurWeb.StatusLive.HealthBoard

  @impl true
  def mount(_params, _session, socket) do
    socket = MediaCentaurWeb.Live.Subscriptions.subscribe(socket, Console)

    {:ok,
     socket
     |> assign(page_title: "Console", scope: nil, filter: nil)
     |> assign(:buffer_size, Console.config().cap)
     |> assign(:app_components, View.app_components())
     |> assign(:framework_components, View.framework_components())
     # Stream limit is pinned at the whole-store ceiling and never
     # reconfigured. Phoenix LiveView forbids stream_configure/3 after a
     # stream has been populated, so a dynamic limit would crash on resize.
     # Negative: lines append at the live edge, so the oldest are trimmed.
     |> stream_configure(:entries,
       dom_id: &Logic.entry_dom_id/1,
       limit: -Buffer.whole_store_limit()
     )}
  end

  # The scope is the URL's; the filter follows from it. The first paint reads
  # the store (ADR-051: a pure in-memory read belongs on the first paint),
  # capped at the default per-component size — the store may hold far more
  # on a bumped cap, but the first viewport never needs that many; new lines
  # arrive over PubSub. Component and level are applied in the store by
  # `Console.read/2`, so excluded entries never paint.
  @impl true
  def handle_params(params, _uri, socket) do
    scope = Logic.scope(params)
    filter = if scope, do: HealthBoard.log_filter(scope), else: Console.get_filter()

    {:noreply,
     socket
     |> assign(scope: scope, filter: filter)
     |> redraw(Buffer.default_cap())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- The console has no sidebar entry; it belongs with Status, where
          every drill-in links to it. --%>
    <Layouts.app
      show_social={@show_social}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/status"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
      full_width
    >
      <div
        id="console-page"
        class="console-page glass-surface"
        phx-hook="ConsolePage"
        data-nav-default-zone="console"
      >
        <MediaCentaurWeb.ConsoleComponents.chip_row
          filter={@filter}
          scope={@scope}
          app_components={@app_components}
          framework_components={@framework_components}
        />
        <MediaCentaurWeb.ConsoleComponents.log_view
          id="console"
          stream={@streams.entries}
          class="console-log"
        />
        <MediaCentaurWeb.ConsoleComponents.action_footer buffer_size={@buffer_size} />
      </div>
    </Layouts.app>
    """
  end

  # The stream reset to what the store holds under the current filter,
  # oldest first.
  defp redraw(socket, limit) do
    visible = Console.read(socket.assigns.filter, limit)
    stream(socket, :entries, Enum.reverse(visible), reset: true)
  end

  # A scoped visit owns its filter; otherwise the saved filter is edited and
  # its `{:filter_changed, _}` broadcast redraws every unscoped console.
  defp change_filter(%{assigns: %{scope: nil}} = socket, %Filter{} = filter) do
    :ok = Console.update_filter(filter)
    socket
  end

  defp change_filter(socket, %Filter{} = filter) do
    socket |> assign(:filter, filter) |> redraw(Buffer.whole_store_limit())
  end

  # Download and copy both hand over everything the store holds under the
  # current filter and the browser's text search — a person saving the log
  # wants the whole thing, not the first-paint window.
  defp visible_payload(socket, query) do
    socket.assigns.filter
    |> Console.read(Buffer.whole_store_limit())
    |> Logic.format_visible_payload(query)
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:log_entries, entries}, socket) do
    # Chronological batch (Buffer flushes ~100ms windows), appended at the
    # live edge in order.
    socket =
      entries
      |> Enum.filter(&Filter.matches?(&1, socket.assigns.filter))
      |> Enum.reduce(socket, fn entry, acc -> stream_insert(acc, :entries, entry, at: -1) end)

    {:noreply, socket}
  end

  def handle_info(:buffer_cleared, socket) do
    {:noreply, stream(socket, :entries, [], reset: true)}
  end

  def handle_info({:buffer_resized, new_cap}, socket) do
    # Phoenix LiveView does NOT allow stream_configure/3 after the stream
    # has been populated (raises ArgumentError). The stream limit was fixed
    # at the whole-store ceiling in mount; the Buffer itself enforces the
    # user's chosen cap. On resize we just reset the stream contents to
    # match the newly-truncated buffer — so read the whole store and let
    # the new cap do the truncating.
    {:noreply,
     socket
     |> assign(:buffer_size, new_cap)
     |> redraw(Buffer.whole_store_limit())}
  end

  # The saved filter changed. A scoped visit holds its own and ignores it.
  def handle_info({:filter_changed, _filter}, %{assigns: %{scope: scope}} = socket) when scope != nil do
    {:noreply, socket}
  end

  def handle_info({:filter_changed, filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> redraw(Buffer.whole_store_limit())}
  end

  # Session-wide on_mount hooks (ShellBadges) subscribe this view to their
  # PubSub topics and pass messages through — without a catch-all, any such
  # broadcast while the console page is open is a FunctionClauseError.
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Event handlers ---

  @impl true
  def handle_event("toggle_component", %{"component" => component_string}, socket) do
    filter = Logic.toggle_component(socket.assigns.filter, component_string)
    {:noreply, change_filter(socket, filter)}
  end

  def handle_event("set_level", %{"level" => level_string}, socket) do
    filter = Logic.set_level(socket.assigns.filter, level_string)
    {:noreply, change_filter(socket, filter)}
  end

  def handle_event("clear_buffer", _params, socket) do
    :ok = Console.clear()
    {:noreply, socket}
  end

  def handle_event("resize_buffer", %{"size" => size_string}, socket) do
    case Logic.parse_buffer_size(size_string) do
      {:ok, size} -> Console.resize(size)
      :invalid -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("rescan_library", _params, socket) do
    MediaCentaur.Watcher.Rescan.scan_async()
    {:noreply, socket}
  end

  # Copy and download carry the browser's text search (`search`).
  def handle_event("download_buffer", params, socket) do
    payload = visible_payload(socket, Map.get(params, "search", ""))
    filename = Logic.download_filename()

    {:noreply, push_event(socket, "console:download", %{filename: filename, content: payload})}
  end

  def handle_event("copy_visible", params, socket) do
    payload = visible_payload(socket, Map.get(params, "search", ""))
    {:noreply, push_event(socket, "console:copy", %{content: payload})}
  end
end
