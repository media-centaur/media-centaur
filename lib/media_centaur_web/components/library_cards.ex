defmodule MediaCentaurWeb.Components.LibraryCards do
  @moduledoc """
  Presentation components for the library page — poster cards, continue-watching
  cards, and the browse toolbar.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [image_url: 2]

  import MediaCentaurWeb.LibraryHelpers,
    only: [compute_progress_fraction: 1, format_type: 1, extract_year: 1, format_resume_parts: 2]

  # --- Poster Card ---

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :selected, :boolean, default: false
  attr :playing, :boolean, default: false

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
        @selected && "ring-2 ring-primary",
        @playing && "ring-2 ring-primary"
      ]}
    >
      <%!-- Poster --%>
      <div class="aspect-[2/3] glass-inset relative">
        <img
          :if={@poster}
          src={@poster}
          class="w-full h-full object-cover"
          loading="lazy"
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

  # --- Continue Watching Card ---

  attr :entry, :map, required: true
  attr :resume, :map, default: nil
  attr :playing, :boolean, default: false

  def cw_card(assigns) do
    entity = assigns.entry.entity
    backdrop = image_url(entity, "backdrop")
    background = backdrop || image_url(entity, "poster")
    logo = image_url(entity, "logo")
    progress_fraction = compute_progress_fraction(assigns.entry.progress)
    entry = assigns.entry
    {resume_label, time_remaining} = format_resume_parts(assigns.resume, entry)

    assigns =
      assign(assigns,
        background: background,
        logo: logo,
        progress_fraction: progress_fraction,
        resume_label: resume_label,
        time_remaining: time_remaining
      )

    ~H"""
    <div
      phx-click="select_cw_entity"
      phx-value-id={@entry.entity.id}
      phx-mounted={
        JS.transition({"", "opacity-0 translate-y-1", "opacity-100 translate-y-0"}, time: 200)
      }
      data-nav-item
      data-entity-id={@entry.entity.id}
      tabindex="0"
      class={[
        "relative rounded-lg overflow-hidden cursor-pointer group",
        "hover:scale-[1.02] hover:shadow-xl transition-transform",
        @playing && "ring-2 ring-primary"
      ]}
    >
      <div class="aspect-video glass-inset relative">
        <img
          :if={@background}
          src={@background}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div :if={!@background} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>

        <div class="absolute inset-0 bg-gradient-to-t from-black/88 via-black/40 via-40% to-transparent" />

        <div class="absolute bottom-4 left-4 right-4">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-14 max-w-[70%] object-contain drop-shadow-[0_2px_12px_rgba(0,0,0,0.7)] mb-2"
          />
          <h3
            :if={!@logo}
            class="text-lg font-bold text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)] mb-2"
          >
            {@entry.entity.name}
          </h3>

          <div class="flex items-center justify-between">
            <span :if={@resume_label} class="text-sm text-primary font-medium drop-shadow">
              {@resume_label}
            </span>
            <span
              :if={@time_remaining}
              class="text-sm text-base-content/70 font-medium drop-shadow ml-auto"
            >
              {@time_remaining}
            </span>
          </div>
        </div>

        <div
          :if={@playing}
          class="absolute top-3 right-3 size-3 rounded-full bg-primary animate-pulse"
        />

        <div
          :if={@progress_fraction > 0}
          class="absolute bottom-0 left-0 right-0 h-1 bg-base-content/20"
        >
          <div class="h-full bg-primary progress-fill" style={"width: #{@progress_fraction}%"} />
        </div>
      </div>
    </div>
    """
  end

  def cw_empty(assigns) do
    ~H"""
    <div class="text-base-content/50 py-6 text-center text-sm empty-state-enter">
      Nothing in progress. Switch to the Library tab to start watching.
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
