defmodule MediaCentarrWeb.Components.LibraryCards do
  @moduledoc """
  Presentation components for the library page — poster cards and the browse
  toolbar.
  """

  use MediaCentarrWeb, :html

  import MediaCentarrWeb.LiveHelpers, only: [image_url: 2]

  import MediaCentarrWeb.LibraryFormatters, only: [format_type: 1, extract_year: 1]
  import MediaCentarrWeb.LibraryProgress, only: [compute_progress_fraction: 1]

  # --- Poster Card ---

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :selected, :boolean, default: false
  attr :playing, :boolean, default: false
  attr :available, :boolean, default: true

  def poster_card(assigns) do
    entity = assigns.entry.entity
    poster = image_url(entity, "poster")
    assigns = assign(assigns, :poster, poster)

    ~H"""
    <div
      id={@id}
      phx-click="select_entity"
      phx-value-id={@entry.entity.id}
      phx-mounted={
        JS.transition({"", "opacity-0 translate-y-1", "opacity-100 translate-y-0"}, time: 200)
      }
      data-nav-item
      data-entity-id={@entry.entity.id}
      tabindex="0"
      class={[
        "card glass-surface cursor-pointer overflow-hidden poster-card",
        "hover:ring-1 hover:ring-base-content/20",
        @selected && "ring-2 ring-primary"
      ]}
    >
      <%!-- Poster --%>
      <div class="aspect-[2/3] glass-inset relative">
        <img
          :if={@poster && @available}
          src={@poster}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div
          :if={@poster && !@available}
          class="w-full h-full bg-base-content/5"
          aria-label="Artwork unavailable — storage not mounted"
        />
        <div :if={!@poster} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-8 text-base-content/20" />
        </div>

        <%!-- Now-playing pulse --%>
        <div
          :if={@playing}
          class="absolute top-2 right-2 size-3 rounded-full bg-primary animate-pulse"
        />

        <%!-- Progress bar --%>
        <.card_progress_bar progress={@entry.progress} />
      </div>

      <%!-- Card footer --%>
      <div class="p-2">
        <div class="text-sm font-medium leading-tight line-clamp-2">
          {@entry.entity.name || "Untitled"}
        </div>
        <div class="mt-0.5 text-xs text-base-content/50">
          {format_type(@entry.entity.type)}<span :if={@entry.entity.date_published}> · {extract_year(@entry.entity.date_published)}</span>
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
    fraction = compute_progress_fraction(progress)
    assigns = assign(assigns, :fraction, fraction)

    ~H"""
    <div :if={@fraction > 0} class="absolute bottom-0 left-0 right-0 h-[3px] bg-base-content/20">
      <div class="h-full bg-primary progress-fill" style={"width: #{@fraction}%"} />
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

  @sort_options [{:recent, "Recently Added"}, {:alpha, "A–Z"}, {:year, "Year"}]

  attr :active_tab, :atom, required: true
  attr :counts, :map, required: true
  attr :sort_order, :atom, required: true
  attr :sort_open, :boolean, required: true
  attr :sort_highlight, :integer, required: true
  attr :filter_text, :string, required: true

  def toolbar(assigns) do
    assigns = assign(assigns, :sort_options, @sort_options)

    ~H"""
    <div class="flex items-center gap-4 flex-wrap" data-nav-zone="toolbar">
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
          <span class="badge badge-sm ml-1">{@counts[tab] || 0}</span>
        </button>
      </div>

      <div
        class="sort-dropdown"
        phx-click-away="close_sort"
        phx-keydown="sort_key"
        data-nav-item
        data-sort={@sort_order}
        data-captures-keys={@sort_open}
        tabindex="0"
      >
        <div class="sort-dropdown-trigger" phx-click="toggle_sort">
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

      <form phx-change="filter" class="ml-auto">
        <input
          id="library-filter"
          type="text"
          name="filter_text"
          value={@filter_text}
          placeholder="Filter by name…"
          phx-debounce="150"
          class="input library-filter w-48"
          data-nav-item
          tabindex="0"
        />
      </form>
    </div>
    """
  end

  defp sort_label(:recent), do: "Recently Added"
  defp sort_label(:alpha), do: "A–Z"
  defp sort_label(:year), do: "Year"
end
