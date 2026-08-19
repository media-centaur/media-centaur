defmodule MediaCentaurWeb.Components.LibraryCards do
  @moduledoc """
  Presentation components for the library page — poster cards and the browse
  toolbar.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LibraryFormatters, only: [format_type: 1]
  import MediaCentaurWeb.LiveHelpers, only: [poster_src: 1]

  alias MediaCentaur.Library.ContinueWatchingProgress
  alias MediaCentaurWeb.Components.PlayOverlay

  # --- Poster Card ---

  attr :id, :string, required: true

  attr :entry, MediaCentaur.Library.Views.BrowseItem,
    required: true,
    doc:
      "A `Library.Views.BrowseItem` struct produced by the Browse projection (Library Schema v2 Phase 3.1). Carries the minimal display shape — `:id`, `:kind`, `:name`, `:date_published`, `:year`, `:poster_url`, `:rank`."

  attr :progress, :map,
    default: nil,
    doc:
      "Progress summary for this entry — `nil` when the entry has no `WatchProgress` row, otherwise a map with `:episodes_completed` / `:episodes_total` and `:episode_position_seconds` / `:episode_duration_seconds`. The progress bar shows the entry-wide watched share via `ContinueWatchingProgress.compute_pct/1` — same measure as the Continue Watching row and the detail hairline."

  attr :selected, :boolean, default: false
  attr :playing, :boolean, default: false
  attr :available, :boolean, default: true

  attr :show_info, :boolean,
    default: true,
    doc:
      "When false, hides the title + type/year footer beneath the poster — for the wall-of-posters view. Driven by the `library_show_card_info` Settings entry (see `MediaCentaur.Settings.Preferences.LibraryCardInfo`)."

  attr :show_play_button, :boolean,
    default: true,
    doc:
      "When false, suppresses the hover play overlay (UIDR-027). Driven by the `card_play_button` Settings entry (see `MediaCentaur.Settings.Preferences.CardPlayButton`)."

  def poster_card(assigns) do
    ~H"""
    <div
      id={@id}
      phx-click="select_entity"
      phx-value-id={@entry.id}
      data-nav-item
      data-entity-id={@entry.id}
      tabindex="0"
      class={[
        "card glass-surface cursor-pointer overflow-hidden poster-card",
        "hover:ring-1 hover:ring-base-content/20",
        @selected && "ring-2 ring-primary"
      ]}
    >
      <%!-- Poster --%>
      <div class="aspect-[2/3] glass-inset relative play-overlay-host">
        <img
          :if={@entry.poster_url && @available}
          src={poster_src(@entry.poster_url)}
          class="w-full h-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <div
          :if={@entry.poster_url && !@available}
          class="w-full h-full bg-base-content/5"
          aria-label="Artwork unavailable — storage not mounted"
        />
        <div :if={!@entry.poster_url} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-8 text-base-content/20" />
        </div>

        <%!-- Direct play (UIDR-027). Collections are filing, not content
              (UIDR-025) — the shelf card never plays; offline artwork
              means the file can't play either. --%>
        <PlayOverlay.play_overlay
          :if={@show_play_button && @available && @entry.kind != :movie_series}
          entity_id={@entry.id}
        />

        <%!-- Now-playing pulse --%>
        <div
          :if={@playing}
          class="absolute top-2 right-2 size-3 rounded-full bg-primary animate-pulse"
        />

        <%!-- Progress bar --%>
        <.card_progress_bar progress={@progress} />
      </div>

      <%!-- Card footer --%>
      <div :if={@show_info} class="p-2">
        <div class="text-sm font-medium leading-tight line-clamp-2">
          {@entry.name || "Untitled"}
        </div>
        <div class="mt-0.5 text-xs text-base-content/50">
          {format_type(@entry.kind)}<span :if={@entry.year}> · {@entry.year}</span>
        </div>
      </div>
    </div>
    """
  end

  defp card_progress_bar(%{progress: nil} = assigns) do
    ~H"""
    """
  end

  defp card_progress_bar(%{progress: progress} = assigns) do
    percent = ContinueWatchingProgress.compute_pct(progress)
    assigns = assign(assigns, :percent, percent)

    ~H"""
    <div :if={@percent > 0} class="absolute bottom-0 left-0 right-0 h-[3px] bg-base-content/20">
      <div class="h-full bg-primary progress-fill" style={"width: #{@percent}%"} />
    </div>
    """
  end

  # --- Storage Offline Banner ---

  @doc """
  Renders a persistent top-of-page notice when one or more watch
  directories are offline. `summary` is a pre-formatted one-liner
  (see `LibraryHelpers.offline_summary/2`).
  """
  attr :summary, :string, required: true

  def storage_offline_banner(assigns) do
    ~H"""
    <div class="mb-4 glass-surface rounded-lg p-3 flex items-start gap-3 border border-warning/30">
      <.icon name="hero-exclamation-triangle" class="size-5 text-warning shrink-0 mt-0.5" />
      <div class="min-w-0">
        <p class="text-sm font-medium">Storage offline</p>
        <p class="text-xs text-base-content/60 mt-0.5">
          {@summary}
        </p>
      </div>
    </div>
    """
  end

  # --- Toolbar ---

  # Order must match `LibraryLive.@sort_options` — the LiveView's
  # keyboard highlight index and this rendered menu index one list each.
  @sort_options [
    {:recent, "Recently Added"},
    {:watched, "Recently Watched"},
    {:alpha, "A–Z"},
    {:year, "Year"}
  ]

  attr :active_tab, :atom, required: true
  attr :sort_order, :atom, required: true
  attr :sort_open, :boolean, required: true
  attr :sort_highlight, :integer, required: true
  attr :filter_text, :string, required: true

  def toolbar(assigns) do
    assigns = assign(assigns, :sort_options, @sort_options)

    ~H"""
    <%!-- The toolbar is the page's topmost context: revealing it means showing
          the page header above it too, so it declares its resting place — a
          `start` alignment plus `.nav-reveal-page-top`'s oversized
          scroll-margin, which clamps the reveal glide to the very top of the
          page. Never scroll the window from the page behavior instead: an
          instant jump fights the glide in flight (see library_behavior.js). --%>
    <div
      class="flex items-center gap-3 flex-wrap nav-reveal-page-top"
      data-nav-zone="toolbar"
      data-nav-reveal
      data-nav-reveal-block="start"
    >
      <%!-- Left cluster: type tabs + sort, bound tightly as "shape the list" controls --%>
      <div class="flex items-center gap-2">
        <div role="tablist" class="tabs tabs-boxed library-tabs w-fit">
          <button
            :for={{tab, label} <- [{:all, "All"}, {:movies, "Movies"}, {:tv, "TV"}]}
            role="tab"
            class={["tab", @active_tab == tab && "tab-active"]}
            phx-click="switch_tab"
            phx-value-tab={tab}
            data-nav-item
            tabindex="0"
          >
            {label}
          </button>
        </div>

        <div
          class="sort-dropdown"
          phx-click="toggle_sort"
          phx-click-away="close_sort"
          phx-keydown="sort_key"
          data-nav-item
          data-sort={@sort_order}
          data-captures-keys={@sort_open}
          tabindex="0"
        >
          <div class="sort-dropdown-trigger">
            {sort_label(@sort_order)}
            <span class={["sort-dropdown-chevron", @sort_open && "rotate-180"]}>
              <.icon name="hero-chevron-down-mini" class="size-4" />
            </span>
          </div>
          <ul :if={@sort_open} class="sort-dropdown-menu glass-surface">
            <li
              :for={{{value, label}, index} <- Enum.with_index(@sort_options)}
              class={[
                "sort-dropdown-item",
                @sort_order == value && "sort-dropdown-item-active",
                @sort_highlight == index && "sort-dropdown-item-highlight"
              ]}
              phx-click="sort"
              phx-value-sort={value}
            >
              {label}
            </li>
          </ul>
        </div>
      </div>

      <form phx-change="filter" class="ml-auto">
        <div class="library-filter-wrap">
          <.icon name="hero-magnifying-glass-mini" class="library-filter-icon" />
          <input
            id="library-filter"
            type="text"
            name="filter_text"
            value={@filter_text}
            placeholder="Filter by name…"
            phx-debounce="150"
            class="input library-filter w-56"
            data-nav-item
            tabindex="0"
          />
          <button
            :if={@filter_text != ""}
            type="button"
            phx-click="clear_filter"
            class="library-filter-clear"
            aria-label="Clear search"
            tabindex="0"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp sort_label(:recent), do: "Recently Added"
  defp sort_label(:watched), do: "Recently Watched"
  defp sort_label(:alpha), do: "A–Z"
  defp sort_label(:year), do: "Year"
end
