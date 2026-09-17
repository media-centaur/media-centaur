defmodule MediaCentaurWeb.ConsoleComponents do
  @moduledoc """
  Shared HEEx function components used by both `ConsoleLive` (sticky drawer)
  and `ConsolePageLive` (full-page `/console` route). Pure render functions
  driven entirely by assigns — no state, no PubSub.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Log stream is sticky LiveView state — covered by page smoke tests"

  use MediaCentaurWeb, :html

  alias MediaCentaur.Console.{Entry, Filter, View}

  @doc """
  Header row with component chips, level filter, and search input.

  ## Attributes

  - `:filter` — the current `%Filter{}` struct
  - `:app_components` — list of app component atoms
  - `:framework_components` — list of framework component atoms
  """
  attr :filter, Filter, required: true

  attr :app_components, :list,
    required: true,
    doc:
      "list of app component atoms (`:watcher`, `:pipeline`, `:tmdb`, …). Element type is `atom()` — primitive list, no struct needed."

  attr :framework_components, :list,
    required: true,
    doc:
      "list of framework component atoms (`:phoenix`, `:ecto`, `:live_view`, …). Element type is `atom()` — primitive list."

  def chip_row(assigns) do
    ~H"""
    <header class="console-header">
      <div class="console-chips">
        <span class="console-chip-group-label">app</span>
        <button
          :for={component <- @app_components}
          type="button"
          class={[
            "console-chip",
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
            "console-chip",
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
  One log row: timestamp, optional component badge, message.

  Carries no container of its own, so the same row serves both the console's
  stream (`log_list/1`) and the Status subsystem panel's plain list.
  """
  # No story file: this module is `@storybook_status :skip`, and the row's
  # rendered states — levels, and with/without the component badge — are
  # exercised through `storybook/health/health_drill_in.story.exs`.
  attr :entry, Entry, required: true

  attr :id, :string,
    default: nil,
    doc:
      "DOM id. `log_list/1` sets it to the stream's dom_id — stream identity is the stream's business; surfaces without a stream leave it nil."

  attr :show_component, :boolean,
    default: true,
    doc: "render the component badge; false on single-component surfaces where it is noise"

  def log_line(assigns) do
    ~H"""
    <div
      id={@id}
      class={["console-entry", View.level_color(@entry.level)]}
      data-level={@entry.level}
      data-component={@entry.component}
      data-message={View.entry_search_text(@entry)}
    >
      <span class="console-timestamp">{View.format_timestamp(@entry.timestamp)}</span>
      <span
        :if={@show_component}
        class={["console-component-badge", View.component_badge_class(@entry.component)]}
      >
        {View.component_label(@entry.component)}
      </span>
      <span class="console-message">{@entry.message}</span>
    </div>
    """
  end

  @doc """
  Log entry list — iterates the entries stream and renders each entry.

  ## Attributes

  - `:streams` — the socket streams map; must contain `:entries`
  """
  attr :streams, :any,
    required: true,
    doc:
      "Phoenix LiveView Streams map (`%Phoenix.LiveView.LiveStream{}` per key). Iterated via `phx-update=\"stream\"`. Phoenix attr has no Streams type — `:any` with this waiver is the canonical pattern."

  def log_list(assigns) do
    ~H"""
    <main class="console-log" id="console-entries" phx-update="stream" phx-hook="LogTail">
      <%!-- The row stays a direct child of `.console-log`: the container is a
            flex column with a gap, and the drawer's client-side search hides
            matched-out rows with `display: none`. A wrapper element would keep
            its gap slot and leave a ladder of holes through a filtered list. --%>
      <.log_line :for={{dom_id, entry} <- @streams.entries} id={dom_id} entry={entry} />
    </main>
    """
  end

  @doc """
  Renders the systemd journal stream. Same visual shell as `log_list` but
  driven by `@streams.journal`. Every entry is `component: :systemd`, so
  we skip the component badge and only render the message line — the
  journalctl timestamp is already baked into `entry.message`.
  """
  attr :streams, :any,
    required: true,
    doc:
      "Phoenix LiveView Streams map; reads `@streams.journal`. Same `phx-update=\"stream\"` pattern as `log_list/1` — see that attr's note for the type rationale."

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
  - `:buffer_size` — current per-component buffer capacity
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
        <form id="console-buffer-size-form" phx-change="resize_buffer">
          <input
            type="range"
            name="size"
            min="100"
            max="1000"
            step="100"
            value={@buffer_size}
            class="range range-xs"
          />
        </form>
        <span class="console-buffer-size-label text-xs">{@buffer_size} / subsystem</span>
      </div>
    </footer>
    """
  end
end
