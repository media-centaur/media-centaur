defmodule MediaCentaurWeb.ConsolePageLive do
  @moduledoc """
  Full-page `/console` route. Same data and events as the sticky drawer,
  different layout: full viewport instead of a half-height dropdown.

  Shares filter/buffer state with `ConsoleLive` via
  `MediaCentaur.Console.Buffer` (single source of truth in the supervision
  tree). PubSub keeps both in sync. Shared behavior lives in
  `MediaCentaurWeb.ConsoleLive.Logic` so the drawer and the full-page route
  can't drift.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Console
  alias MediaCentaur.Console.{Buffer, View}
  alias MediaCentaurWeb.ConsoleLive.Logic

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Console.subscribe()
    end

    snapshot =
      if connected?(socket) do
        Console.snapshot()
      else
        Logic.initial_snapshot()
      end

    socket =
      socket
      |> assign(:filter, snapshot.filter)
      |> assign(:paused, false)
      |> assign(:buffer_size, snapshot.cap)
      |> assign(:app_components, View.app_components())
      |> assign(:framework_components, View.framework_components())
      # See ConsoleLive.mount/3 — stream limit is pinned at max_cap and
      # never reconfigured. Phoenix LV forbids stream_configure after the
      # stream is populated.
      |> stream_configure(:entries,
        dom_id: &Logic.entry_dom_id/1,
        limit: -Buffer.max_cap()
      )
      |> stream(:entries, Enum.reverse(snapshot.entries))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="console-fullpage">
      <MediaCentaurWeb.ConsoleComponents.chip_row
        filter={@filter}
        app_components={@app_components}
        framework_components={@framework_components}
      />
      <MediaCentaurWeb.ConsoleComponents.log_list streams={@streams} />
      <MediaCentaurWeb.ConsoleComponents.action_footer
        paused={@paused}
        buffer_size={@buffer_size}
        show_fullpage_link={false}
      />
    </div>
    """
  end

  @impl true
  def handle_info({:log_entry, entry}, socket) do
    if Logic.should_insert_entry?(socket.assigns.filter, socket.assigns.paused, entry) do
      {:noreply, stream_insert(socket, :entries, entry, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:buffer_cleared, socket) do
    {:noreply, stream(socket, :entries, [], reset: true)}
  end

  def handle_info({:buffer_resized, new_cap}, socket) do
    # See ConsoleLive — stream limit is pinned at max_cap; on resize we only
    # reset the stream contents, never reconfigure it.
    visible = Logic.visible_entries(Console.snapshot(), socket.assigns.filter)

    socket =
      socket
      |> assign(:buffer_size, new_cap)
      |> stream(:entries, Enum.reverse(visible), reset: true)

    {:noreply, socket}
  end

  def handle_info({:filter_changed, filter}, socket) do
    if View.only_search_query_differs?(socket.assigns.filter, filter) do
      # Text search is handled by the client-side hook via data-message
      # attributes — no server-side re-stream needed. Just update the
      # assign so cross-tab sync works without the cursor jump that a
      # re-stream would cause.
      {:noreply, assign(socket, :filter, filter)}
    else
      visible = Logic.visible_entries(Console.snapshot(), filter)

      socket =
        socket
        |> assign(:filter, filter)
        |> stream(:entries, Enum.reverse(visible), reset: true)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_component", %{"component" => component_string}, socket) do
    :ok = Console.update_filter(Logic.toggle_component(socket.assigns.filter, component_string))
    {:noreply, socket}
  end

  def handle_event("solo_component", %{"component" => component_string}, socket) do
    :ok = Console.update_filter(Logic.solo_component(socket.assigns.filter, component_string))
    {:noreply, socket}
  end

  def handle_event("mute_component", %{"component" => component_string}, socket) do
    :ok = Console.update_filter(Logic.mute_component(socket.assigns.filter, component_string))
    {:noreply, socket}
  end

  def handle_event("set_level", %{"level" => level_string}, socket) do
    :ok = Console.update_filter(Logic.set_level(socket.assigns.filter, level_string))
    {:noreply, socket}
  end

  def handle_event("search", %{"value" => query}, socket) do
    new_filter = Logic.set_search(socket.assigns.filter, query)
    :ok = Console.update_filter(new_filter)
    {:noreply, assign(socket, :filter, new_filter)}
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
    :ok = Console.rescan_library()
    {:noreply, socket}
  end

  def handle_event("download_buffer", _params, socket) do
    snapshot = Console.snapshot()
    payload = Logic.format_visible_payload(snapshot.entries, socket.assigns.filter)
    filename = Logic.download_filename()

    {:noreply, push_event(socket, "console:download", %{filename: filename, content: payload})}
  end

  def handle_event("copy_visible", _params, socket) do
    snapshot = Console.snapshot()
    payload = Logic.format_visible_payload(snapshot.entries, socket.assigns.filter)

    {:noreply, push_event(socket, "console:copy", %{content: payload})}
  end
end
