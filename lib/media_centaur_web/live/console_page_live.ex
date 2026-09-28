defmodule MediaCentaurWeb.ConsolePageLive do
  @moduledoc """
  Full-page `/console` route — the diagnostic firehose: every component's
  log ring, filtered by component chips and a level floor, with pause,
  clear, resize, copy and download. The text search is the browser's: the
  `ConsolePage` hook hides non-matching rows, keeps the query across
  reloads, and sends it with copy and download.

  Reachable by URL only. It is deliberately unlinked from the shell: the
  everyday path to a subsystem's logs is the Status board's drill-in panel,
  and the systemd journal lives on Status → System. `/console` is what you
  open when you need all of it at once.

  Filter and buffer state lives in `MediaCentaur.Console.Buffer` (single
  source of truth in the supervision tree); PubSub keeps this view in sync
  with it. Pure decision logic (filter mutation, visibility, payload
  formatting) lives in `MediaCentaurWeb.ConsolePageLive.Logic` (ADR-030).
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Console
  alias MediaCentaur.Console.{Buffer, View}
  alias MediaCentaurWeb.ConsolePageLive.Logic

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Console") |> mount_console_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="console-page" class="console-fullpage" phx-hook="ConsolePage">
      <MediaCentaurWeb.ConsoleComponents.chip_row
        filter={@filter}
        app_components={@app_components}
        framework_components={@framework_components}
      />
      <MediaCentaurWeb.ConsoleComponents.log_list streams={@streams} />
      <MediaCentaurWeb.ConsoleComponents.action_footer
        paused={@paused}
        buffer_size={@buffer_size}
      />
    </div>
    """
  end

  # --- Mount setup ---

  defp mount_console_state(socket) do
    socket = MediaCentaurWeb.Live.Subscriptions.subscribe(socket, Console)

    config = Console.config()

    # The first paint reads the buffer (ADR-051: a pure in-memory read
    # belongs on the first paint). Cap it at the default per-component
    # size — the store may hold far more across its rings on a bumped
    # cap, but the initial viewport never needs that many; new entries
    # arrive via PubSub.
    #
    # The filter reaches the entries before they reach the stream, exactly
    # like every other entry-producing path (`should_insert_entry?` on new
    # entries, `:filter_changed`, `:buffer_resized`). Streaming an
    # unfiltered window here was the one path that bypassed the filter, so
    # excluded entries (hidden components, below-floor levels) painted on
    # first load and were only scrolled away by later live entries — the
    # "flash of unfiltered text". Component and level are applied *in the
    # store* by `Console.read/2`, which is strictly stronger than filtering
    # before streaming: excluded entries never leave the buffer.
    visible_entries = Console.read(config.filter, Buffer.default_cap())

    socket
    |> assign(:filter, config.filter)
    |> assign(:paused, false)
    |> assign(:buffer_size, config.cap)
    |> assign(:app_components, View.app_components())
    |> assign(:framework_components, View.framework_components())
    # Stream limit is pinned at the whole-store ceiling and never
    # reconfigured. Phoenix LiveView forbids stream_configure/3 after a
    # stream has been populated, so a dynamic limit would crash on resize.
    |> stream_configure(:entries,
      dom_id: &Logic.entry_dom_id/1,
      limit: -Buffer.whole_store_limit()
    )
    |> stream(:entries, Enum.reverse(visible_entries))
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
    # Chronological batch (Buffer flushes ~100ms windows); inserting
    # each at 0 leaves the newest entry first, same as the old
    # per-line contract.
    socket =
      entries
      |> Enum.filter(&Logic.should_insert_entry?(socket.assigns.filter, socket.assigns.paused, &1))
      |> Enum.reduce(socket, fn entry, acc -> stream_insert(acc, :entries, entry, at: 0) end)

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
    visible = Console.read(socket.assigns.filter, Buffer.whole_store_limit())

    socket =
      socket
      |> assign(:buffer_size, new_cap)
      |> stream(:entries, Enum.reverse(visible), reset: true)

    {:noreply, socket}
  end

  # Same redraw as a resize: the stream is reset to everything the store
  # holds under the new filter.
  def handle_info({:filter_changed, filter}, socket) do
    visible = Console.read(filter, Buffer.whole_store_limit())

    socket =
      socket
      |> assign(:filter, filter)
      |> stream(:entries, Enum.reverse(visible), reset: true)

    {:noreply, socket}
  end

  # Session-wide on_mount hooks (ShellBadges) subscribe this view to their
  # PubSub topics and pass messages through — without a catch-all, any such
  # broadcast while the console page is open is a FunctionClauseError.
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Event handlers ---

  @impl true
  def handle_event("toggle_component", %{"component" => component_string}, socket) do
    :ok = Console.update_filter(Logic.toggle_component(socket.assigns.filter, component_string))

    {:noreply, socket}
  end

  def handle_event("set_level", %{"level" => level_string}, socket) do
    :ok = Console.update_filter(Logic.set_level(socket.assigns.filter, level_string))
    {:noreply, socket}
  end

  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, not socket.assigns.paused)}
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
