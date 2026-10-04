defmodule MediaCentaurWeb.ConsoleComponents do
  @moduledoc """
  HEEx function components for the `/console` page (`ConsolePageLive`).
  `log_view/1` and `log_line/1` are also imported by `HealthComponents` for
  the Status drill-in's journal and log preview. Pure render functions driven entirely by assigns —
  no state, no PubSub.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "chip_row and action_footer are the console page's own wiring, covered by its tests; log_view (and the log_line it draws) has storybook/console/log_view.story.exs"

  use MediaCentaurWeb, :html

  alias MediaCentaur.Console.{Entry, Filter, View}
  alias MediaCentaurWeb.StatusLive.HealthBoard

  @doc """
  Header row with component chips, level filter, and search input.

  ## Attributes

  - `:filter` — the current `%Filter{}` struct
  - `:scope` — the subsystem a scoped visit shows, or nil
  - `:app_components` — list of app component atoms
  - `:framework_components` — list of framework component atoms
  """
  attr :filter, Filter, required: true

  attr :scope, :atom,
    default: nil,
    doc: "the Status subsystem this visit is scoped to (`/console?subsystem=…`), or nil"

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
    <header class="console-header" data-nav-zone="toolbar">
      <div :if={@scope} class="flex items-center gap-2">
        <span class="text-sm font-medium">{HealthBoard.label(@scope)} logs</span>
        <.button variant="dismiss" size="xs" patch={~p"/console"} data-nav-item tabindex="0">
          Show all logs
        </.button>
        <.button
          variant="dismiss"
          size="xs"
          navigate={~p"/status?subsystem=#{@scope}"}
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-arrow-left-mini" class="size-3.5" /> Status
        </.button>
        <span class="console-chip-divider" aria-hidden="true"></span>
      </div>
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
          data-nav-item
          tabindex="0"
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
          data-nav-item
          tabindex="0"
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
          data-nav-item
          tabindex="0"
        >
          {level}
        </button>
      </div>

      <input
        id="console-search-input"
        type="text"
        class="input input-sm console-search"
        placeholder="search..."
        name="search-query"
        data-console-search
        data-nav-item
        tabindex="0"
      />
    </header>
    """
  end

  @doc """
  One log row: timestamp, optional component badge, message.

  Carries no container of its own, so the same row serves a `log_view/1` and
  the Status subsystem log preview's plain list.
  """
  # No story file of its own: the row's rendered states — levels, and
  # with/without the component badge and timestamp — are exercised through
  # `storybook/console/log_view.story.exs`.
  attr :entry, Entry, required: true

  attr :id, :string,
    default: nil,
    doc:
      "DOM id. `log_view/1` sets it to the stream's dom_id, or derives one from the entry id for a list; the preview leaves it nil."

  attr :show_component, :boolean,
    default: true,
    doc: "render the component badge; false on single-component surfaces where it is noise"

  attr :show_timestamp, :boolean,
    default: true,
    doc:
      "render the entry's arrival time; false where the source writes its own timestamp into the message (the systemd journal), which would otherwise print twice — and disagree, because a backlog seeded on subscribe all arrives at once"

  def log_line(assigns) do
    ~H"""
    <div
      id={@id}
      class={["console-entry", View.level_color(@entry.level)]}
      data-level={@entry.level}
      data-component={@entry.component}
      data-message={View.entry_search_text(@entry)}
    >
      <span :if={@show_timestamp} class="console-timestamp">
        {View.format_timestamp(@entry.timestamp)}
      </span>
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
  A log view: log lines in a scroller, oldest at the top and newest at the
  bottom (the live edge), which follows the live edge or holds the reader's
  place. The `LogFollow` hook owns that state (`assets/js/hooks/log_follow.js`
  carries the contract); while held, the jump control under the rows counts
  the lines that arrived and scrolls back to the live edge.

  Takes the rows as a LiveView stream (`stream`, the console) or as a list
  (`lines`, the systemd journal), oldest first either way.
  """
  attr :id, :string, required: true

  attr :stream, :any,
    default: nil,
    doc:
      "a `%Phoenix.LiveView.LiveStream{}` of entries, appended at the live edge. Phoenix attr has no stream type — `:any` with this waiver is the canonical pattern."

  attr :lines, :list, default: [], doc: "[Console.Entry.t()] oldest first, when there is no stream"
  attr :show_component, :boolean, default: true
  attr :show_timestamp, :boolean, default: true
  attr :class, :any, default: nil, doc: "sizing for the scroller: a height bound or a flex share"

  def log_view(assigns) do
    ~H"""
    <div id={@id} class={["log-view", @class]} phx-hook="LogFollow">
      <%!-- Rows stay direct children of the rows container: it is a flex
            column with a gap, and the console's search hides matched-out rows
            with `display: none`. A wrapper element would keep its gap slot
            and leave a ladder of holes through a filtered list. --%>
      <div
        :if={@stream}
        id={"#{@id}-rows"}
        class="log-view-rows"
        phx-update="stream"
        data-log-rows
      >
        <.log_line
          :for={{dom_id, entry} <- @stream}
          id={dom_id}
          entry={entry}
          show_component={@show_component}
          show_timestamp={@show_timestamp}
        />
      </div>
      <div :if={!@stream} id={"#{@id}-rows"} class="log-view-rows" data-log-rows>
        <.log_line
          :for={entry <- @lines}
          id={"#{@id}-#{entry.id}"}
          entry={entry}
          show_component={@show_component}
          show_timestamp={@show_timestamp}
        />
      </div>
      <%!-- The hook shows, hides and labels the control; `ignore` keeps a
            patch from resetting what it set. --%>
      <div id={"#{@id}-jump"} class="log-view-jump" phx-update="ignore">
        <.button variant="secondary" size="xs" type="button" data-log-jump hidden>
          <span data-log-jump-label>Jump to latest</span>
          <.icon name="hero-arrow-down-mini" class="size-3.5" />
        </.button>
      </div>
    </div>
    """
  end

  @doc """
  Footer with buffer management actions and size slider.

  ## Attributes

  - `:buffer_size` — current per-component buffer capacity
  """
  attr :buffer_size, :integer, required: true

  def action_footer(assigns) do
    ~H"""
    <%!-- The size slider stays off the nav graph: LEFT and RIGHT move along
          the footer, so a focused range input could never be adjusted. Tab
          still reaches it. --%>
    <footer class="console-footer" data-nav-zone="console_footer">
      <.button
        variant="neutral"
        size="xs"
        data-nav-item
        tabindex="0"
        phx-click="clear_buffer"
        data-confirm="Clear the diagnostic log buffer? Recent entries will be lost."
      >
        clear
      </.button>
      <%!-- The ConsolePage hook answers these: it pushes the event with the
            browser's text search, which the server does not hold. --%>
      <.button
        variant="neutral"
        size="xs"
        data-nav-item
        tabindex="0"
        phx-click={JS.dispatch("console:request", detail: %{event: "copy_visible"})}
      >
        copy
      </.button>
      <.button
        variant="neutral"
        size="xs"
        data-nav-item
        tabindex="0"
        phx-click={JS.dispatch("console:request", detail: %{event: "download_buffer"})}
      >
        download
      </.button>
      <.button
        variant="primary"
        size="xs"
        data-nav-item
        tabindex="0"
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
            phx-debounce="300"
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
