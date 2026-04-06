defmodule MediaCentaurWeb.ConsoleLive do
  @moduledoc """
  Sticky dropdown console — always mounted via `MediaCentaurWeb.Layouts.console_mount/1`
  from each page LiveView. Receives log entries via PubSub and renders them into
  a LiveView stream with filtering, pause, clear, resize, download, and copy actions.

  Shared behavior (mount setup, PubSub handlers, event handlers) lives in
  `MediaCentaurWeb.ConsoleLive.Shared`. Pure logic (filter mutation, visibility
  decisions, payload formatting) lives in `MediaCentaurWeb.ConsoleLive.Logic`.
  This module is thin wiring: mount options, render, and the drawer-open toggle
  that is unique to the sticky UI.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.ConsoleLive.Shared

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:open, false) |> console_mount(), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="console-sticky-root"
      class="console-overlay"
      data-state={if @open, do: "open", else: "closed"}
      phx-hook="Console"
    >
      <div class="console-panel glass-surface" data-captures-keys={@open && "true"}>
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
    </div>
    """
  end

  # --- Drawer-specific event ---

  @impl true
  def handle_event("toggle_console", _params, socket) do
    # Open/close state lives on the server so morphdom never reverts it on
    # LiveView re-renders. The JS hook pushes this event on backtick, Escape,
    # and backdrop click. This is the one event unique to the sticky drawer —
    # ConsolePageLive has no drawer to toggle.
    {:noreply, assign(socket, :open, not socket.assigns.open)}
  end
end
