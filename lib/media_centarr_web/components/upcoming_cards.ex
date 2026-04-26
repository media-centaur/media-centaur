defmodule MediaCentarrWeb.Components.UpcomingCards do
  @moduledoc """
  Components for the Upcoming releases zone — calendar view with release cards.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import MediaCentarrWeb.CoreComponents

  @weekdays ~w(Mon Tue Wed Thu Fri Sat Sun)

  # --- Main component ---

  attr :releases, :map, required: true
  attr :events, :list, required: true
  attr :images, :map, default: %{}
  attr :calendar_month, :any, required: true
  attr :selected_day, :any, default: nil
  attr :tracked_items, :list, default: []
  attr :confirm_stop_item, :any, default: nil
  attr :tmdb_ready, :boolean, default: true
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  def upcoming_zone(assigns) do
    {year, month} = assigns.calendar_month
    today = Date.utc_today()

    all_releases = assigns.releases.upcoming ++ assigns.releases.released
    by_date = releases_by_date(all_releases)
    weeks = calendar_weeks(year, month)
    no_date = Enum.filter(assigns.releases.upcoming, &is_nil(&1.air_date))

    month_label = Calendar.strftime(Date.new!(year, month, 1), "%B %Y")

    selected_releases =
      if assigns.selected_day do
        Map.get(by_date, assigns.selected_day, [])
      end

    assigns =
      assigns
      |> assign(:today, today)
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:month_label, month_label)
      |> assign(:weeks, weeks)
      |> assign(:by_date, by_date)
      |> assign(:no_date, no_date)
      |> assign(:released, assigns.releases.released)
      |> assign(:dated_upcoming, Enum.filter(assigns.releases.upcoming, & &1.air_date))
      |> assign(:tracked_items, assigns.tracked_items)
      |> assign(:selected_releases, selected_releases)
      |> assign(:weekdays, @weekdays)

    ~H"""
    <div>
      <%!-- Section navigation zone — uses CSS grid so all nav items are direct
           children (the > selector in config.js requires it). The 2-column layout
           lets "Now Available" and "Upcoming" sit side-by-side on large screens
           while everything else spans both columns. --%>
      <div data-nav-zone="upcoming" class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%!-- Calendar section (nav item wraps header + grid — left/right changes month) --%>
        <div
          data-nav-item
          data-section-type="calendar"
          tabindex="0"
          class="lg:col-span-2 space-y-6 rounded-xl outline-none p-3"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <button phx-click="prev_month" class="btn btn-ghost btn-sm btn-square" tabindex="-1">
                <.icon name="hero-chevron-left-mini" class="size-5" />
              </button>
              <h2 class="text-lg font-semibold min-w-[10rem] text-center">{@month_label}</h2>
              <button phx-click="next_month" class="btn btn-ghost btn-sm btn-square" tabindex="-1">
                <.icon name="hero-chevron-right-mini" class="size-5" />
              </button>
              <button
                phx-click="jump_today"
                class="btn btn-ghost btn-xs ml-2 text-base-content/50"
                tabindex="-1"
              >
                Today
              </button>
            </div>
            <button
              :if={@tmdb_ready}
              phx-click={JS.push("open_track_modal") |> JS.focus(to: "#track-search-input")}
              class="btn btn-soft btn-primary btn-sm"
              tabindex="-1"
            >
              <.icon name="hero-plus-mini" class="size-4" /> Track New Releases
            </button>
          </div>

          <div class="rounded-xl overflow-hidden border border-base-content/15">
            <div class="grid grid-cols-7 bg-base-200/30">
              <div
                :for={day <- @weekdays}
                class="py-2 text-center text-xs font-medium uppercase tracking-wider text-base-content/40"
              >
                {day}
              </div>
            </div>
            <div :for={week <- @weeks} class="grid grid-cols-7 border-t border-base-content/15">
              <.calendar_cell
                :for={date <- week}
                date={date}
                month={@month}
                today={@today}
                releases={Map.get(@by_date, date, [])}
                images={@images}
                selected={@selected_day == date}
              />
            </div>
          </div>
        </div>

        <%!-- Selected day detail (not a nav item) --%>
        <div :if={@selected_releases} class="lg:col-span-2">
          <.day_detail
            day={@selected_day}
            releases={@selected_releases}
            images={@images}
            grab_statuses={@grab_statuses}
            acquisition_ready={@acquisition_ready}
          />
        </div>

        <%!-- Now Available (takes 1 column on lg — sits beside Upcoming) --%>
        <div
          data-nav-item
          data-section-type="now-available"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-4 glass-inset"
        >
          <h3 class="text-sm font-medium text-success uppercase tracking-wider">Now Available</h3>
          <%= if @released != [] do %>
            <.released_content
              releases={@released}
              grab_statuses={@grab_statuses}
              acquisition_ready={@acquisition_ready}
            />
          <% else %>
            <p class="text-sm text-base-content/50">No recent releases.</p>
          <% end %>
        </div>

        <%!-- Upcoming (takes 1 column on lg — sits beside Now Available) --%>
        <div
          data-nav-item
          data-section-type="upcoming-list"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-4 glass-inset"
        >
          <h3 class="text-sm font-medium text-info uppercase tracking-wider">Upcoming</h3>
          <%= if @dated_upcoming != [] do %>
            <.upcoming_list_content
              releases={@dated_upcoming}
              grab_statuses={@grab_statuses}
              acquisition_ready={@acquisition_ready}
            />
          <% else %>
            <p class="text-sm text-base-content/50">Nothing scheduled.</p>
          <% end %>
        </div>

        <%!-- Recent Changes (events) — paired with Tracking on lg --%>
        <div
          data-nav-item
          data-section-type="events"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-4 glass-inset"
        >
          <h3 class="text-sm font-medium text-base-content/50 uppercase tracking-wider">
            Recent Changes
          </h3>
          <%= if @events != [] do %>
            <div class="release-grid text-sm pl-3">
              <div :for={event <- @events} class="release-row group">
                <span class="text-base-content/30 tabular-nums text-right">
                  {format_datetime(event.inserted_at)}
                </span>
                <span class="font-medium">{event.item_name}</span>
                <span class="text-base-content/40">{event_label(event)}</span>
                <.view_activity_link
                  title={event.item_name}
                  acquisition_ready={@acquisition_ready}
                  class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 transition-opacity"
                />
              </div>
            </div>
          <% else %>
            <p class="text-sm text-base-content/50">No recent changes.</p>
          <% end %>
        </div>

        <%!-- Tracking — paired with Recent Changes on lg --%>
        <div
          data-nav-item
          data-section-type="tracking"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-4 glass-inset"
        >
          <h3 class="text-sm font-medium text-base-content/50 uppercase tracking-wider">
            Tracking
          </h3>
          <%= if @tracked_items != [] do %>
            <div
              data-nav-zone="grid"
              data-nav-grid
              class="tracking-grid text-sm pl-3"
            >
              <.tracked_item_row
                :for={item <- @tracked_items}
                item={item}
                acquisition_ready={@acquisition_ready}
              />
            </div>
          <% else %>
            <p class="text-sm text-base-content/50">Nothing tracked yet.</p>
          <% end %>
        </div>

        <%!-- Unscheduled section — still spans both columns because list can be long --%>
        <div
          :if={@no_date != []}
          data-nav-item
          data-section-type="unscheduled"
          tabindex="0"
          class="lg:col-span-2 space-y-3 rounded-xl outline-none p-3"
        >
          <h3 class="text-sm font-medium text-base-content/40 uppercase tracking-wider">
            Unscheduled
          </h3>
          <.unscheduled_content releases={@no_date} />
        </div>
      </div>

      <%!-- Stop tracking confirmation modal --%>
      <.stop_tracking_modal item={@confirm_stop_item} />
    </div>
    """
  end

  # --- Calendar cell ---

  attr :date, Date, required: true
  attr :month, :integer, required: true
  attr :today, Date, required: true
  attr :releases, :list, default: []
  attr :images, :map, default: %{}
  attr :selected, :boolean, default: false

  defp calendar_cell(assigns) do
    in_month = assigns.date.month == assigns.month
    is_today = assigns.date == assigns.today
    has_releases = assigns.releases != []
    is_past = Date.before?(assigns.date, assigns.today)
    release_count = length(assigns.releases)

    # For single releases, extract the backdrop for full-cell fill
    solo_backdrop =
      if release_count == 1 do
        item = hd(assigns.releases).item
        item_images = Map.get(assigns.images, item.id, %{})
        item_images[:backdrop]
      end

    # For 2+ releases, prepare visible tiles (cap at 4) and overflow count
    visible_releases = Enum.take(assigns.releases, 4)
    overflow_count = max(release_count - 4, 0)

    assigns =
      assigns
      |> assign(:in_month, in_month)
      |> assign(:is_today, is_today)
      |> assign(:has_releases, has_releases)
      |> assign(:is_past, is_past)
      |> assign(:release_count, release_count)
      |> assign(:solo_backdrop, solo_backdrop)
      |> assign(:visible_releases, visible_releases)
      |> assign(:overflow_count, overflow_count)

    ~H"""
    <div
      class={[
        "relative min-h-[5rem] p-1.5 border-r border-base-content/15 last:border-r-0 transition-colors overflow-hidden",
        !@in_month && "bg-base-200/10",
        @selected && "z-10",
        @has_releases && @in_month && "cursor-pointer hover:bg-base-content/5",
        @is_past && @has_releases && "opacity-50"
      ]}
      phx-click={@has_releases && @in_month && "select_day"}
      phx-value-date={@has_releases && @in_month && Date.to_iso8601(@date)}
    >
      <%!-- === 1 release: full-cell backdrop === --%>
      <img
        :if={@release_count == 1 && @solo_backdrop && @in_month}
        src={@solo_backdrop}
        class="absolute inset-0 w-full h-full object-cover object-top"
        loading="lazy"
      />
      <div
        :if={@release_count == 1 && @solo_backdrop && @in_month}
        class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-black/40"
      />

      <%!-- Day number (z-10 to sit above backdrop) --%>
      <div class="relative z-10 flex items-start justify-between mb-1">
        <span class={[
          "text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full",
          @is_today && "bg-primary text-primary-content",
          !@is_today && @has_releases && @in_month && "bg-black/90 text-white",
          !@is_today && !@has_releases && @in_month && "text-base-content/60",
          !@is_today && !@in_month && "text-base-content/15"
        ]}>
          {@date.day}
        </span>
      </div>

      <%!-- 1 release: show name at bottom --%>
      <span
        :if={@release_count == 1 && @in_month}
        class="absolute z-10 bottom-0.5 left-1 right-1 text-[9px] font-semibold text-white truncate"
        title={hd(@releases).item.name}
      >
        {hd(@releases).item.name}
      </span>

      <%!-- === 2 releases: side-by-side, full height === --%>
      <div
        :if={@release_count == 2 && @in_month}
        class="absolute inset-0 grid grid-cols-2 overflow-hidden"
      >
        <.release_tile
          :for={release <- @visible_releases}
          release={release}
          images={@images}
        />
      </div>

      <%!-- === 3-4+ releases: 2x2 grid === --%>
      <div
        :if={@release_count >= 3 && @in_month}
        class="absolute inset-0 grid grid-cols-2 grid-rows-2 overflow-hidden"
      >
        <.release_tile
          :for={release <- Enum.take(@visible_releases, if(@overflow_count > 0, do: 3, else: 4))}
          release={release}
          images={@images}
        />
        <%!-- +N overflow tile --%>
        <div
          :if={@overflow_count > 0}
          class="relative bg-base-300/80 flex items-center justify-center"
        >
          <span class="text-sm font-bold text-base-content/60">
            +{@overflow_count + 1}
          </span>
        </div>
      </div>

      <%!-- Selected-day border (z-20 to render above backdrops) --%>
      <div
        :if={@selected}
        class="absolute inset-0 z-20 border-3 border-primary rounded-sm pointer-events-none"
      />
    </div>
    """
  end

  # --- Backdrop tile for calendar cell grids ---

  attr :release, :any, required: true
  attr :images, :map, default: %{}

  defp release_tile(assigns) do
    item = assigns.release.item
    item_images = Map.get(assigns.images, item.id, %{})
    backdrop = item_images[:backdrop]

    assigns =
      assigns
      |> assign(:backdrop, backdrop)
      |> assign(:name, item.name)
      |> assign(:media_type, item.media_type)

    ~H"""
    <div class="relative min-w-0 overflow-hidden" title={@name}>
      <img
        :if={@backdrop}
        src={@backdrop}
        class="w-full h-full object-cover object-top"
        loading="lazy"
      />
      <div
        :if={!@backdrop}
        class={[
          "w-full h-full",
          @media_type == :tv_series && "bg-info/20",
          @media_type == :movie && "bg-warning/20"
        ]}
      />
      <div class="absolute inset-0 bg-gradient-to-t from-black/70 to-transparent" />
      <span class="absolute bottom-0.5 left-1 right-1 text-[9px] font-semibold text-white truncate">
        {@name}
      </span>
    </div>
    """
  end

  # --- Selected day detail panel ---

  attr :day, Date, required: true
  attr :releases, :list, required: true
  attr :images, :map, default: %{}
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  defp day_detail(assigns) do
    ~H"""
    <div class="rounded-xl border border-primary/20 bg-base-200/30 p-4 space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold">
          {Calendar.strftime(@day, "%A, %B %-d")}
        </h3>
        <button phx-click="select_day" phx-value-date="" class="btn btn-ghost btn-xs btn-square">
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
      </div>
      <div class="grid grid-cols-[repeat(auto-fill,minmax(240px,360px))] gap-3">
        <.day_release_card
          :for={release <- @releases}
          release={release}
          images={@images}
          grab_statuses={@grab_statuses}
          acquisition_ready={@acquisition_ready}
        />
      </div>
    </div>
    """
  end

  attr :release, :any, required: true
  attr :images, :map, default: %{}
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  defp day_release_card(assigns) do
    item = assigns.release.item
    item_images = Map.get(assigns.images, item.id, %{})
    backdrop = item_images[:backdrop] || item_images[:poster]
    logo = item_images[:logo]

    subtitle =
      cond do
        assigns.release.season_number ->
          "S#{assigns.release.season_number}E#{assigns.release.episode_number}" <>
            if(assigns.release.title, do: " — \"#{assigns.release.title}\"", else: "")

        assigns.release.title ->
          assigns.release.title

        true ->
          nil
      end

    assigns =
      assigns
      |> assign(:backdrop, backdrop)
      |> assign(:logo, logo)
      |> assign(:name, item.name)
      |> assign(:subtitle, subtitle)
      |> assign(:media_type, item.media_type)
      |> assign(:is_released, assigns.release.released)

    ~H"""
    <div class={["relative rounded-lg overflow-hidden glass-inset", @is_released && "opacity-60"]}>
      <div class="aspect-[21/9] relative">
        <img
          :if={@backdrop}
          src={@backdrop}
          class="w-full h-full object-cover object-top"
          loading="lazy"
        />
        <div :if={!@backdrop} class="w-full h-full flex items-center justify-center bg-base-300">
          <.icon name="hero-film" class="size-6 text-base-content/15" />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/30 via-40% to-transparent" />
        <div class="absolute bottom-2 left-2 right-2">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-6 max-w-[60%] object-contain drop-shadow-[0_1px_4px_rgba(0,0,0,0.7)]"
          />
          <p
            :if={!@logo}
            class="text-sm font-bold text-white drop-shadow-[0_1px_4px_rgba(0,0,0,0.7)] leading-tight truncate"
          >
            {@name}
          </p>
          <p :if={@subtitle} class="text-[11px] text-base-content/60 truncate drop-shadow">
            {@subtitle}
          </p>
        </div>
        <div class="absolute top-1.5 right-1.5 flex gap-1 items-center">
          <.grab_status_badge
            release={@release}
            grab_statuses={@grab_statuses}
            acquisition_ready={@acquisition_ready}
          />
          <span
            :if={@is_released}
            class="text-[9px] font-semibold uppercase tracking-wider px-1 py-0.5 rounded bg-success/20 text-success"
          >
            Out
          </span>
          <span class={[
            "text-[9px] font-semibold uppercase tracking-wider px-1 py-0.5 rounded bg-black/40 backdrop-blur-sm",
            @media_type == :tv_series && "text-info",
            @media_type == :movie && "text-warning"
          ]}>
            {if @media_type == :tv_series, do: "TV", else: "Movie"}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # --- Released section content ---

  attr :releases, :list, required: true
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  defp released_content(assigns) do
    sorted =
      Enum.sort_by(assigns.releases, fn release ->
        date = release.air_date || ~D[9999-12-31]

        {date.year, date.month, date.day, release.item.name, release.season_number || 0,
         release.episode_number || 0}
      end)

    assigns = assign(assigns, :sorted, sorted)

    ~H"""
    <div class="release-grid release-grid-dismissable text-sm pl-3">
      <.release_row
        :for={release <- @sorted}
        release={release}
        grab_statuses={@grab_statuses}
        acquisition_ready={@acquisition_ready}
        dismissable
      />
    </div>
    """
  end

  # --- Upcoming list content ---

  attr :releases, :list, required: true
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  defp upcoming_list_content(assigns) do
    sorted =
      Enum.sort_by(assigns.releases, fn release ->
        date = release.air_date

        {date.year, date.month, date.day, release.item.name, release.season_number || 0,
         release.episode_number || 0}
      end)

    assigns = assign(assigns, :sorted, sorted)

    ~H"""
    <div class="release-grid text-sm pl-3">
      <.release_row
        :for={release <- @sorted}
        release={release}
        grab_statuses={@grab_statuses}
        acquisition_ready={@acquisition_ready}
      />
    </div>
    """
  end

  # --- Unscheduled section content ---

  attr :releases, :list, required: true

  defp unscheduled_content(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <div :for={release <- @releases} class="flex items-baseline gap-2 text-sm pl-3 py-0.5">
        <span class="font-medium">{release.item.name}</span>
        <span :if={release.season_number} class="text-base-content/50">
          <span class="text-[0.8em] text-base-content/30">S</span>{String.pad_leading(
            "#{release.season_number}",
            2,
            "0"
          )}
          <span class="text-[0.8em] text-base-content/30">E</span>{String.pad_leading(
            "#{release.episode_number}",
            2,
            "0"
          )}
        </span>
        <span :if={release.title} class="text-base-content/40">"{release.title}"</span>
      </div>
    </div>
    """
  end

  # --- Release row (shared by released + upcoming lists) ---

  attr :release, :map, required: true
  attr :dismissable, :boolean, default: false
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  defp release_row(assigns) do
    ~H"""
    <div class="release-row group">
      <span class="text-base-content/30 tabular-nums text-right">
        {if @release.air_date, do: Calendar.strftime(@release.air_date, "%b %-d"), else: "—"}
      </span>
      <span class="font-medium truncate">{@release.item.name}</span>
      <.release_detail release={@release} />
      <div class="flex items-center gap-1 justify-end">
        <.grab_status_badge
          release={@release}
          grab_statuses={@grab_statuses}
          acquisition_ready={@acquisition_ready}
        />
        <button
          :if={@dismissable}
          phx-click="dismiss_release"
          phx-value-release-id={@release.id}
          class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 transition-opacity"
          aria-label="Dismiss"
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>
    </div>
    """
  end

  # --- Release detail (episode info or type label) ---

  attr :release, :map, required: true

  defp release_detail(%{release: %{season_number: season}} = assigns) when is_integer(season) do
    ~H"""
    <span class="text-base-content/50 tabular-nums">
      <span class="text-[0.8em] text-base-content/30">S</span>{String.pad_leading(
        "#{@release.season_number}",
        2,
        "0"
      )}
      <span class="text-[0.8em] text-base-content/30">E</span>{String.pad_leading(
        "#{@release.episode_number}",
        2,
        "0"
      )}
    </span>
    <span class="text-base-content/40 truncate">
      {if @release.title, do: "\"#{@release.title}\""}
    </span>
    """
  end

  defp release_detail(%{release: %{release_type: "theatrical"}} = assigns) do
    ~H"""
    <span class="text-warning/70 text-xs col-span-2">In Theaters</span>
    """
  end

  defp release_detail(%{release: %{release_type: "digital"}} = assigns) do
    ~H"""
    <span class="text-info/70 text-xs col-span-2">Streaming</span>
    """
  end

  defp release_detail(assigns) do
    ~H"""
    <span class="col-span-2"></span>
    """
  end

  # --- Tracked item row ---

  attr :item, :map, required: true
  attr :acquisition_ready, :boolean, default: false

  defp tracked_item_row(assigns) do
    ~H"""
    <div
      role="button"
      data-nav-item
      tabindex="0"
      phx-click="stop_tracking"
      phx-value-item-id={@item.item_id}
      class="release-row group cursor-pointer"
      aria-label={"Stop tracking #{@item.name}"}
    >
      <span class={[
        "text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded text-center min-w-10",
        @item.media_type == :tv_series && "bg-info/15 text-info",
        @item.media_type == :movie && "bg-warning/15 text-warning"
      ]}>
        {if @item.media_type == :tv_series, do: "TV", else: "Movie"}
      </span>
      <span class="font-medium truncate">{@item.name}</span>
      <span class="text-base-content/50 text-right">{@item.status_text}</span>
      <div class="flex items-center gap-1 justify-end">
        <.view_activity_link
          title={@item.name}
          acquisition_ready={@acquisition_ready}
          class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity"
        />
        <span
          class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity pointer-events-none"
          aria-hidden="true"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </span>
      </div>
    </div>
    """
  end

  # --- Stop tracking confirmation modal ---

  attr :item, :any, default: nil

  defp stop_tracking_modal(assigns) do
    open = assigns.item != nil

    assigns = assign(assigns, :open, open)

    ~H"""
    <div
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      data-detail-mode={@open && "modal"}
      data-dismiss-event={@open && "cancel_stop_tracking"}
      phx-click={@open && "cancel_stop_tracking"}
      phx-window-keydown={@open && "cancel_stop_tracking"}
      phx-key="Escape"
      style="z-index: 60;"
    >
      <div class="modal-panel modal-panel-sm p-6" phx-click={%Phoenix.LiveView.JS{}}>
        <div :if={@item}>
          <h3 class="text-lg font-bold text-error">Stop tracking?</h3>
          <p class="mt-2 text-sm text-base-content/70">
            Stop tracking <span class="font-semibold">{@item.name}</span>?
            You won't see upcoming releases for this title anymore.
          </p>
          <div class="mt-4 flex justify-end gap-2">
            <button
              data-nav-item
              tabindex="0"
              phx-click="cancel_stop_tracking"
              class="btn btn-ghost btn-sm"
            >
              Cancel
            </button>
            <button
              data-nav-item
              tabindex="0"
              phx-click="confirm_stop_tracking"
              class="btn btn-soft btn-error btn-sm"
            >
              Stop tracking
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Calendar helpers ---

  @weekdays_attr @weekdays
  def weekdays, do: @weekdays_attr

  defp calendar_weeks(year, month) do
    first = Date.new!(year, month, 1)
    start_pad = Date.day_of_week(first) - 1
    start = Date.add(first, -start_pad)

    Enum.reject(
      Enum.map(0..5, fn week ->
        Enum.map(0..6, fn day ->
          Date.add(start, week * 7 + day)
        end)
      end),
      fn week -> Enum.all?(week, &(&1.month != month)) end
    )
  end

  defp releases_by_date(releases) do
    releases
    |> Enum.filter(& &1.air_date)
    |> Enum.group_by(& &1.air_date)
  end

  defp event_label(%{event_type: :began_tracking}), do: "began tracking"
  defp event_label(%{event_type: :stopped_tracking}), do: "stopped tracking"
  defp event_label(%{event_type: :removed_from_schedule}), do: "removed from schedule"
  defp event_label(event), do: event.description

  # --- Format helpers ---

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_date()
    |> Calendar.strftime("%B %-d, %Y")
  end

  # ---------------------------------------------------------------------------
  # Acquisition cross-link helpers
  #
  # When the acquisition pipeline is enabled (Prowlarr connected), every
  # release card and tracked-item row links to the unified Downloads page,
  # so users can pivot from "what's coming" to "what's being grabbed"
  # without hunting. All helpers no-op when `acquisition_ready` is false
  # — release tracking remains useful without acquisition.
  # ---------------------------------------------------------------------------

  alias Phoenix.LiveView.JS

  attr :release, :map, required: true
  attr :grab_statuses, :map, default: %{}
  attr :acquisition_ready, :boolean, default: false

  defp grab_status_badge(assigns) do
    grab =
      if assigns.acquisition_ready,
        do: lookup_grab(assigns.release, assigns.grab_statuses)

    assigns = assign(assigns, grab: grab)

    ~H"""
    <.link
      :if={@grab}
      navigate={"/download?filter=all&search=" <> URI.encode_www_form(@release.item.name)}
      class={["badge badge-sm whitespace-nowrap", grab_status_class(@grab.status)]}
      title={"Open in Downloads — " <> grab_status_label(@grab)}
    >
      {grab_status_label(@grab)}
    </.link>
    """
  end

  attr :title, :string, required: true
  attr :acquisition_ready, :boolean, default: false
  attr :class, :string, default: "btn btn-ghost btn-xs"

  defp view_activity_link(assigns) do
    ~H"""
    <.link
      :if={@acquisition_ready}
      navigate={"/download?filter=all&search=" <> URI.encode_www_form(@title)}
      class={@class}
      title={"View “" <> @title <> "” in Downloads"}
      onclick="event.stopPropagation()"
    >
      <.icon name="hero-arrow-down-tray-mini" class="size-3.5" />
    </.link>
    """
  end

  defp lookup_grab(release, grab_statuses) do
    key =
      {to_string(release.item.tmdb_id), to_string(release.item.media_type), release.season_number,
       release.episode_number}

    Map.get(grab_statuses, key)
  end

  defp grab_status_label(%{status: "grabbed", quality: q}) when is_binary(q), do: "Grabbed " <> q

  defp grab_status_label(%{status: "grabbed"}), do: "Grabbed"
  defp grab_status_label(%{status: "snoozed"}), do: "Snoozed"
  defp grab_status_label(%{status: "searching"}), do: "Searching"
  defp grab_status_label(%{status: "abandoned"}), do: "Abandoned"
  defp grab_status_label(%{status: "cancelled"}), do: "Cancelled"
  defp grab_status_label(%{status: status}), do: status

  defp grab_status_class("grabbed"), do: "badge-success"
  defp grab_status_class("snoozed"), do: "badge-warning"
  defp grab_status_class("searching"), do: "badge-info"
  defp grab_status_class("abandoned"), do: "badge-error"
  defp grab_status_class("cancelled"), do: "badge-ghost"
  defp grab_status_class(_), do: "badge-ghost"
end
