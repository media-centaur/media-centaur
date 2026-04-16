defmodule MediaCentarrWeb.ConsolePageLive do
  @moduledoc """
  Full-page `/console` route. Same data and events as the sticky drawer,
  different layout: full viewport instead of a half-height dropdown.

  Shares filter/buffer state with `ConsoleLive` via
  `MediaCentarr.Console.Buffer` (single source of truth in the supervision
  tree). PubSub keeps both in sync. Shared behavior lives in
  `MediaCentarrWeb.ConsoleLive.Shared` so the drawer and the full-page route
  can't drift.
  """
  use MediaCentarrWeb, :live_view
  use MediaCentarrWeb.ConsoleLive.Shared

  @impl true
  def mount(_params, _session, socket) do
    {:ok, console_mount(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="console-fullpage">
      <MediaCentarrWeb.ConsoleComponents.chip_row
        filter={@filter}
        app_components={@app_components}
        framework_components={@framework_components}
      />
      <MediaCentarrWeb.ConsoleComponents.log_list streams={@streams} />
      <MediaCentarrWeb.ConsoleComponents.action_footer
        paused={@paused}
        buffer_size={@buffer_size}
        show_fullpage_link={false}
      />
    </div>
    """
  end
end
