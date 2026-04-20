defmodule MediaCentarrWeb.ConsoleLive.Shared do
  @moduledoc """
  Shared wiring for `ConsoleLive` (sticky drawer) and `ConsolePageLive`
  (full-page `/console` route).

  Both views subscribe to the same PubSub topic, render the same stream of
  log entries, and handle the same set of user events. The only differences
  are layout (`layout: false` for the sticky drawer) and the drawer-toggle
  event that only the sticky version needs.

  This module injects:
  - `console_mount/1` — shared mount setup (subscribe, snapshot, assigns, stream)
  - 4 `handle_info` clauses for PubSub messages
  - 11 `handle_event` clauses for user interactions

  Pure decision logic lives in `ConsoleLive.Logic` (ADR-030) and is unchanged.
  """

  defmacro __using__(_opts) do
    quote do
      alias MediaCentarr.Console
      alias MediaCentarr.Console.{Buffer, View}
      alias MediaCentarrWeb.ConsoleLive.Logic

      # --- Shared mount setup ---

      @doc false
      defp console_mount(socket) do
        if connected?(socket) do
          Console.subscribe()
        end

        snapshot =
          if connected?(socket) do
            Console.snapshot()
          else
            Logic.initial_snapshot()
          end

        journal_available =
          if connected?(socket), do: Console.journal_available?(), else: false

        socket
        |> assign(:filter, snapshot.filter)
        |> assign(:paused, false)
        |> assign(:buffer_size, snapshot.cap)
        |> assign(:app_components, View.app_components())
        |> assign(:framework_components, View.framework_components())
        |> assign(:active_source, :app)
        |> assign(:journal_available, journal_available)
        # Stream limit is pinned at the buffer's max_cap and never reconfigured.
        # Phoenix LiveView forbids stream_configure/3 after a stream has been
        # populated, so a dynamic limit would crash on resize. The buffer itself
        # caps entries at the user-chosen size; the stream just mirrors whatever
        # the buffer delivers.
        |> stream_configure(:entries,
          dom_id: &Logic.entry_dom_id/1,
          limit: -Buffer.max_cap()
        )
        |> stream(:entries, Enum.reverse(snapshot.entries))
        |> stream_configure(:journal, dom_id: &Logic.entry_dom_id/1, limit: -500)
        |> stream(:journal, [])
      end

      # --- PubSub handlers ---

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
        # Phoenix LiveView does NOT allow stream_configure/3 after the stream
        # has been populated (raises ArgumentError). The stream limit was fixed
        # at Buffer.max_cap() in mount; the Buffer itself enforces the user's
        # chosen cap. On resize we just reset the stream contents to match the
        # newly-truncated buffer.
        visible = Logic.visible_entries(Console.snapshot(), socket.assigns.filter)

        socket =
          socket
          |> assign(:buffer_size, new_cap)
          |> stream(:entries, Enum.reverse(visible), reset: true)

        {:noreply, socket}
      end

      def handle_info({:journal_line, entry}, socket) do
        if socket.assigns.active_source == :systemd and not socket.assigns.paused do
          # Append at the tail so the render order matches `journalctl -f`:
          # oldest at the top, newest at the bottom. The LogTail hook
          # (data-pin-to="bottom" on the journal <main>) keeps the scroll
          # glued to the live edge.
          {:noreply, stream_insert(socket, :journal, entry, at: -1)}
        else
          {:noreply, socket}
        end
      end

      def handle_info({:journal_reset}, socket) do
        if socket.assigns.active_source == :systemd do
          snapshot = Console.journal_snapshot()
          {:noreply, stream(socket, :journal, snapshot, reset: true)}
        else
          {:noreply, socket}
        end
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

      # --- Event handlers ---

      @impl true
      def handle_event("toggle_component", %{"component" => component_string}, socket) do
        :ok =
          Console.update_filter(Logic.toggle_component(socket.assigns.filter, component_string))

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
        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          MediaCentarr.Watcher.Supervisor.scan()
        end)

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

      def handle_event("set_log_source", %{"source" => source_string}, socket) do
        new_source = if source_string == "systemd", do: :systemd, else: :app

        cond do
          new_source == socket.assigns.active_source ->
            {:noreply, socket}

          new_source == :systemd ->
            case Console.journal_subscribe() do
              {:ok, entries} ->
                # Preserve chronological order (oldest-first) so the hook
                # can tail-follow the bottom edge.
                {:noreply,
                 socket
                 |> assign(:active_source, :systemd)
                 |> stream(:journal, entries, reset: true)}

              {:error, :no_unit_detected} ->
                {:noreply, assign(socket, :journal_available, false)}
            end

          true ->
            :ok = Console.journal_unsubscribe()

            {:noreply,
             socket
             |> assign(:active_source, :app)
             |> stream(:journal, [], reset: true)}
        end
      end

      def handle_event("reconnect_journal", _params, socket) do
        _ = Console.journal_reconnect()
        {:noreply, socket}
      end

      @impl true
      def terminate(_reason, socket) do
        # Best-effort — if the LiveView was on the Systemd tab when the
        # socket closed, release its journal subscription. JournalSource
        # monitors subscribers and will reap this pid anyway via :DOWN,
        # but explicit unsubscribe makes the refcount behaviour
        # predictable in tests.
        if socket.assigns[:active_source] == :systemd do
          _ = Console.journal_unsubscribe()
        end

        :ok
      end
    end
  end
end
