defmodule MediaCentaurWeb.ConsolePageLive do
  @moduledoc """
  Full-page `/console` route. Same data and events as the sticky drawer,
  different layout: full viewport instead of a half-height dropdown.

  Shares filter/buffer state with `ConsoleLive` via
  `MediaCentaur.Console.Buffer` (single source of truth in the supervision
  tree). PubSub keeps both in sync. Shared behavior lives in
  `MediaCentaurWeb.ConsoleLive.Shared` so the drawer and the full-page route
  can't drift.
  """
  use MediaCentaurWeb, :live_view
  use MediaCentaurWeb.ConsoleLive.Shared

  @impl true
  def mount(_params, _session, socket) do
    {:ok, console_mount(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="console-fullpage">
      <MediaCentaurWeb.ConsoleComponents.source_tabs
        active_source={@active_source}
        journal_available={@journal_available}
      />
      <MediaCentaurWeb.ConsoleComponents.chip_row
        :if={@active_source == :app}
        filter={@filter}
        app_components={@app_components}
        framework_components={@framework_components}
      />
      <MediaCentaurWeb.ConsoleComponents.log_list
        :if={@active_source == :app}
        streams={@streams}
      />
      <MediaCentaurWeb.ConsoleComponents.journal_list
        :if={@active_source == :systemd}
        streams={@streams}
      />
      <MediaCentaurWeb.ConsoleComponents.action_footer
        paused={@paused}
        buffer_size={@buffer_size}
        show_fullpage_link={false}
      />
    </div>
    """
  end
end
