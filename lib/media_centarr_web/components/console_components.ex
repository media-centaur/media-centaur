defmodule MediaCentarrWeb.ConsoleComponents do
  @moduledoc """
  Shared HEEx function components used by both `ConsoleLive` (sticky drawer)
  and `ConsolePageLive` (full-page `/console` route). Pure render functions
  driven entirely by assigns — no state, no PubSub.
  """
  use MediaCentarrWeb, :html

  alias MediaCentarr.Console.View

  @doc """
  Header row with component chips, level filter, and search input.

  ## Attributes

  - `:filter` — the current `%Filter{}` struct
  - `:app_components` — list of app component atoms
  - `:framework_components` — list of framework component atoms
  """
  attr :filter, :any, required: true
  attr :app_components, :list, required: true
  attr :framework_components, :list, required: true

  def chip_row(assigns) do
    ~H"""
    <header class="console-header">
      <div class="console-chips">
        <span class="console-chip-group-label">app</span>
        <button
          :for={component <- @app_components}
          type="button"
          class={[
            "badge badge-sm console-chip",
            View.component_badge_class(component),
            View.chip_state_class(@filter, component)
          ]}
          phx-click="toggle_component"
          phx-value-component={component}
          title={"click to toggle #{component}"}
        >
          {View.component_label(component)}
        </button>

        <span class="console-chip-divider" aria-hidden="true"></span>
        <span class="console-chip-group-label">framework</span>

        <button
          :for={component <- @framework_components}
          type="button"
          class={[
            "badge badge-sm console-chip",
            View.component_badge_class(component),
            View.chip_state_class(@filter, component)
          ]}
          phx-click="toggle_component"
          phx-value-component={component}
          title={"click to toggle #{component}"}
        >
          {View.component_label(component)}
        </button>
      </div>

      <%!-- :debug is deliberately omitted from the segment — it's captured
            in the buffer (Log.debug would work if added) but v1 hides it
            from the level floor UI to avoid noise. Add here if debug logs
            become a first-class diagnostic surface. --%>
      <div class="console-level-filter join">
        <button
          :for={level <- [:info, :warning, :error]}
          type="button"
          class={["join-item btn btn-xs", View.level_button_class(@filter, level)]}
          phx-click="set_level"
          phx-value-level={level}
        >
          {level}
        </button>
      </div>

      <input
        id="console-search-input"
        type="text"
        class="input input-sm input-bordered console-search"
        placeholder="search..."
        value={@filter.search}
        phx-keyup="search"
        phx-debounce="200"
        name="search-query"
        data-console-search
      />
    </header>
    """
  end

  @doc """
  Log entry list — iterates the entries stream and renders each entry.

  ## Attributes

  - `:streams` — the socket streams map; must contain `:entries`
  """
  attr :streams, :any, required: true

  def log_list(assigns) do
    ~H"""
    <main class="console-log" id="console-entries" phx-update="stream" phx-hook="LogTail">
      <div
        :for={{dom_id, entry} <- @streams.entries}
        id={dom_id}
        class={["console-entry", View.level_color(entry.level)]}
        data-level={entry.level}
        data-component={entry.component}
        data-message={View.entry_search_text(entry)}
      >
        <span class="console-timestamp">{View.format_timestamp(entry.timestamp)}</span>
        <span class={[
          "badge badge-xs console-component-badge",
          View.component_badge_class(entry.component)
        ]}>
          {View.component_label(entry.component)}
        </span>
        <span class="console-message">{entry.message}</span>
      </div>
    </main>
    """
  end

  @doc """
  Renders the systemd journal stream. Same visual shell as `log_list` but
  driven by `@streams.journal`. Every entry is `component: :systemd`, so
  we skip the component badge and only render the message line — the
  journalctl timestamp is already baked into `entry.message`.
  """
  attr :streams, :any, required: true

  def journal_list(assigns) do
    ~H"""
    <main
      class="console-log"
      id="console-journal"
      phx-update="stream"
      phx-hook="LogTail"
      data-pin-to="bottom"
    >
      <div
        :for={{dom_id, entry} <- @streams.journal}
        id={dom_id}
        class="console-entry"
        data-level={entry.level}
        data-component={entry.component}
        data-message={entry.message}
      >
        <span class="console-message">{entry.message}</span>
      </div>
    </main>
    """
  end

  @doc """
  Tab strip for choosing the active log source — "App" is always present;
  "Systemd" appears only when a systemd unit has been detected.

  ## Attributes

  - `:active_source` — `:app` or `:systemd`
  - `:journal_available` — when false, the Systemd tab is hidden entirely
  """
  attr :active_source, :atom, required: true
  attr :journal_available, :boolean, required: true

  def source_tabs(assigns) do
    ~H"""
    <nav class="console-source-tabs" role="tablist" aria-label="Log source">
      <button
        type="button"
        role="tab"
        phx-click="set_log_source"
        phx-value-source="app"
        aria-selected={@active_source == :app}
        class={["console-source-tab", @active_source == :app && "is-active"]}
      >
        App
      </button>
      <button
        :if={@journal_available}
        type="button"
        role="tab"
        phx-click="set_log_source"
        phx-value-source="systemd"
        aria-selected={@active_source == :systemd}
        class={["console-source-tab", @active_source == :systemd && "is-active"]}
      >
        Systemd
      </button>
      <.button
        :if={@active_source == :systemd and @journal_available}
        variant="dismiss"
        size="xs"
        class="console-source-reconnect"
        phx-click="reconnect_journal"
        title="Force-respawn journalctl"
      >
        Reconnect
      </.button>
    </nav>
    """
  end

  @doc """
  Footer with buffer management actions and size slider.

  When `show_fullpage_link` is true (the default), renders a navigation link
  to the full-page `/console` route. Pass `false` from `ConsolePageLive` since
  it IS the full page.

  ## Attributes

  - `:paused` — whether log streaming is paused
  - `:buffer_size` — current buffer capacity
  - `:show_fullpage_link` — whether to render the "full page" link (default: `true`)
  """
  attr :paused, :boolean, required: true
  attr :buffer_size, :integer, required: true
  attr :show_fullpage_link, :boolean, default: true

  def action_footer(assigns) do
    ~H"""
    <footer class="console-footer">
      <.button variant="neutral" size="xs" phx-click="toggle_pause">
        {View.pause_button_label(@paused)}
      </.button>
      <.button
        variant="neutral"
        size="xs"
        phx-click="clear_buffer"
        data-confirm="Clear the diagnostic log buffer? Recent entries will be lost."
      >
        clear
      </.button>
      <.button variant="neutral" size="xs" phx-click="copy_visible">copy</.button>
      <.button variant="neutral" size="xs" phx-click="download_buffer">download</.button>
      <.button :if={@show_fullpage_link} variant="neutral" size="xs" navigate={~p"/console"}>
        full page
      </.button>
      <.button
        variant="primary"
        size="xs"
        phx-click="rescan_library"
        phx-disable-with="scanning…"
      >
        rescan
      </.button>
      <div class="console-buffer-size">
        <form phx-change="resize_buffer">
          <input
            type="range"
            name="size"
            min="100"
            max="50000"
            step="100"
            value={@buffer_size}
            class="range range-xs"
          />
        </form>
        <span class="console-buffer-size-label text-xs">{@buffer_size}</span>
      </div>
    </footer>
    """
  end
end
