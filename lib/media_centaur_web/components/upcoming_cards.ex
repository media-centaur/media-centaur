defmodule MediaCentaurWeb.Components.UpcomingCards do
  @moduledoc """
  Components for the Upcoming releases zone — calendar view with release cards.
  """
  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents

  @weekdays ~w(Mon Tue Wed Thu Fri Sat Sun)

  # --- Main component ---

  attr :releases, :map, required: true
  attr :events, :list, required: true
  attr :images, :map, default: %{}
  attr :scanning, :boolean, default: false
  attr :calendar_month, :any, required: true
  attr :selected_day, :any, default: nil
  attr :confirm_stop_item, :any, default: nil

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
      |> assign(:tracked_items, build_tracked_items(all_releases))
      |> assign(:selected_releases, selected_releases)
      |> assign(:weekdays, @weekdays)

    ~H"""
    <div>
      <%!-- Section navigation zone (uses > selector to avoid counting nested grid items) --%>
      <div data-nav-zone="upcoming" class="space-y-6">
        <%!-- Calendar section (nav item wraps header + grid — left/right changes month) --%>
        <div
          data-nav-item
          data-section-type="calendar"
          tabindex="0"
          class="space-y-6 rounded-xl outline-none p-3"
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
          </div>

          <div class="rounded-xl overflow-hidden border border-base-content/5">
            <div class="grid grid-cols-7 bg-base-200/30">
              <div
                :for={day <- @weekdays}
                class="py-2 text-center text-xs font-medium uppercase tracking-wider text-base-content/40"
              >
                {day}
              </div>
            </div>
            <div :for={week <- @weeks} class="grid grid-cols-7 border-t border-base-content/5">
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
        <.day_detail
          :if={@selected_releases}
          day={@selected_day}
          releases={@selected_releases}
          images={@images}
        />

        <%!-- Now Available section (nav item) --%>
        <div
          :if={@released != []}
          data-nav-item
          data-section-type="now-available"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-3"
        >
          <h3 class="text-sm font-medium text-success uppercase tracking-wider">Now Available</h3>
          <.released_content releases={@released} />
        </div>

        <%!-- Upcoming list section (nav item) --%>
        <div
          :if={@dated_upcoming != []}
          data-nav-item
          data-section-type="upcoming-list"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-3"
        >
          <h3 class="text-sm font-medium text-info uppercase tracking-wider">Upcoming</h3>
          <.upcoming_list_content releases={@dated_upcoming} />
        </div>

        <%!-- Unscheduled section (nav item) --%>
        <div
          :if={@no_date != []}
          data-nav-item
          data-section-type="unscheduled"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-3"
        >
          <h3 class="text-sm font-medium text-base-content/40 uppercase tracking-wider">
            Unscheduled
          </h3>
          <.unscheduled_content releases={@no_date} />
        </div>

        <%!-- Events section (nav item) --%>
        <div
          :if={@events != []}
          data-nav-item
          data-section-type="events"
          tabindex="0"
          class="rounded-xl outline-none p-3"
        >
          <.events_content events={@events} />
        </div>

        <%!-- Tracking section (nav item wraps heading + card grid — SELECT drills in) --%>
        <div
          :if={@tracked_items != []}
          data-nav-item
          data-section-type="tracking"
          tabindex="0"
          class="space-y-3 rounded-xl outline-none p-3"
        >
          <h3 class="text-sm font-medium text-base-content/50 uppercase tracking-wider">
            Tracking
          </h3>
          <div data-nav-zone="grid">
            <div
              data-nav-grid
              class="grid grid-cols-[repeat(auto-fill,minmax(260px,1fr))] gap-3"
            >
              <.tracked_item_card :for={item <- @tracked_items} item={item} images={@images} />
            </div>
          </div>
        </div>

        <%!-- Scan Library button --%>
        <button
          data-nav-item
          data-section-type="scan"
          tabindex="0"
          phx-click="scan_library"
          class="btn btn-soft btn-primary btn-sm"
          disabled={@scanning}
        >
          <.icon name="hero-magnifying-glass-mini" class="size-4" />
          {if @scanning, do: "Scanning…", else: "Scan Library"}
        </button>
      </div>

      <%!-- Empty state --%>
      <div
        :if={map_size(@by_date) == 0 && @no_date == []}
        class="text-center py-12 text-base-content/40"
      >
        <.icon name="hero-calendar-mini" class="size-8 mx-auto mb-2" />
        <p>No upcoming releases tracked</p>
        <p class="text-sm">Click "Scan Library" to find shows and movies with upcoming content</p>
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

    assigns =
      assigns
      |> assign(:in_month, in_month)
      |> assign(:is_today, is_today)
      |> assign(:has_releases, has_releases)
      |> assign(:is_past, is_past)

    ~H"""
    <div
      class={[
        "min-h-[5rem] p-1.5 border-r border-base-content/5 last:border-r-0 transition-colors",
        !@in_month && "bg-base-200/10",
        @selected && "bg-primary/10",
        @has_releases && @in_month && "cursor-pointer hover:bg-base-content/5",
        @is_past && @has_releases && "opacity-50"
      ]}
      phx-click={@has_releases && @in_month && "select_day"}
      phx-value-date={@has_releases && @in_month && Date.to_iso8601(@date)}
    >
      <div class="flex items-start justify-between mb-1">
        <span class={[
          "text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full",
          @is_today && "bg-primary text-primary-content",
          !@is_today && @in_month && "text-base-content/60",
          !@is_today && !@in_month && "text-base-content/15"
        ]}>
          {@date.day}
        </span>
        <span
          :if={@has_releases && length(@releases) > 1}
          class="text-[10px] font-semibold text-base-content/40 bg-base-content/10 rounded-full px-1.5"
        >
          {length(@releases)}
        </span>
      </div>

      <div :if={@has_releases && @in_month} class="flex flex-wrap gap-0.5">
        <.release_dot :for={release <- Enum.take(@releases, 4)} release={release} images={@images} />
      </div>
    </div>
    """
  end

  # --- Release indicator dot/thumb in calendar cell ---

  attr :release, :any, required: true
  attr :images, :map, default: %{}

  defp release_dot(assigns) do
    item = assigns.release.item
    item_images = Map.get(assigns.images, item.id, %{})
    poster = item_images[:poster]

    assigns =
      assigns
      |> assign(:poster, poster)
      |> assign(:name, item.name)
      |> assign(:media_type, item.media_type)

    ~H"""
    <img
      :if={@poster}
      src={@poster}
      title={@name}
      class="w-5 h-7 rounded-sm object-cover"
      loading="lazy"
    />
    <div
      :if={!@poster}
      title={@name}
      class={[
        "w-5 h-2 rounded-full",
        @media_type == :tv_series && "bg-info/60",
        @media_type == :movie && "bg-warning/60"
      ]}
    />
    """
  end

  # --- Selected day detail panel ---

  attr :day, Date, required: true
  attr :releases, :list, required: true
  attr :images, :map, default: %{}

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
      <div class="grid grid-cols-[repeat(auto-fill,minmax(240px,1fr))] gap-3">
        <.day_release_card :for={release <- @releases} release={release} images={@images} />
      </div>
    </div>
    """
  end

  attr :release, :any, required: true
  attr :images, :map, default: %{}

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
          class="w-full h-full object-cover"
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
        <div class="absolute top-1.5 right-1.5 flex gap-1">
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

  defp released_content(assigns) do
    sorted =
      assigns.releases
      |> Enum.sort_by(fn release ->
        date = release.air_date || ~D[9999-12-31]

        {date.year, date.month, date.day, release.item.name, release.season_number || 0,
         release.episode_number || 0}
      end)

    assigns = assign(assigns, :sorted, sorted)

    ~H"""
    <div class="grid grid-cols-[auto_auto_auto_1fr] gap-x-3 gap-y-0.5 text-sm pl-3 items-baseline">
      <%= for release <- @sorted do %>
        <span class="text-base-content/30 tabular-nums text-right">
          {if release.air_date, do: Calendar.strftime(release.air_date, "%b %-d"), else: "—"}
        </span>
        <span class="font-medium truncate">{release.item.name}</span>
        <span class={"text-base-content/50 tabular-nums #{if !release.season_number, do: "col-span-2"}"}>
          <%= if release.season_number do %>
            <span class="text-[0.7em]">S</span>{String.pad_leading("#{release.season_number}", 2, "0")}
            <span class="text-[0.7em]">E</span>{String.pad_leading(
              "#{release.episode_number}",
              2,
              "0"
            )}
          <% end %>
        </span>
        <span :if={release.season_number} class="text-base-content/40 truncate">
          {if release.title, do: "\"#{release.title}\""}
        </span>
      <% end %>
    </div>
    """
  end

  # --- Upcoming list content ---

  attr :releases, :list, required: true

  defp upcoming_list_content(assigns) do
    sorted =
      assigns.releases
      |> Enum.sort_by(fn release ->
        date = release.air_date

        {date.year, date.month, date.day, release.item.name, release.season_number || 0,
         release.episode_number || 0}
      end)

    assigns = assign(assigns, :sorted, sorted)

    ~H"""
    <div class="grid grid-cols-[auto_auto_auto_1fr] gap-x-3 gap-y-0.5 text-sm pl-3 items-baseline">
      <%= for release <- @sorted do %>
        <span class="text-base-content/30 tabular-nums text-right">
          {Calendar.strftime(release.air_date, "%b %-d")}
        </span>
        <span class="font-medium truncate">{release.item.name}</span>
        <span class={"text-base-content/50 tabular-nums #{if !release.season_number, do: "col-span-2"}"}>
          <%= if release.season_number do %>
            <span class="text-[0.7em]">S</span>{String.pad_leading("#{release.season_number}", 2, "0")}
            <span class="text-[0.7em]">E</span>{String.pad_leading(
              "#{release.episode_number}",
              2,
              "0"
            )}
          <% end %>
        </span>
        <span :if={release.season_number} class="text-base-content/40 truncate">
          {if release.title, do: "\"#{release.title}\""}
        </span>
      <% end %>
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
          <span class="text-[0.7em]">S</span>{String.pad_leading("#{release.season_number}", 2, "0")}
          <span class="text-[0.7em]">E</span>{String.pad_leading("#{release.episode_number}", 2, "0")}
        </span>
        <span :if={release.title} class="text-base-content/40">"{release.title}"</span>
      </div>
    </div>
    """
  end

  # --- Events section content ---

  attr :events, :list, required: true

  defp events_content(assigns) do
    ~H"""
    <details open class="collapse collapse-arrow bg-base-200/30 rounded-box">
      <summary class="collapse-title text-sm font-medium text-base-content/50">
        Recent Changes
      </summary>
      <div class="collapse-content space-y-1.5 pt-1">
        <p :for={event <- @events} class="text-sm text-base-content/60">
          <span class="text-base-content/30">{format_datetime(event.inserted_at)}</span>
          <span class="font-medium">{event.item_name}</span>
          <span class="text-base-content/40">
            — {event_label(event)}
          </span>
        </p>
      </div>
    </details>
    """
  end

  # --- Tracked item card ---

  attr :item, :map, required: true
  attr :images, :map, default: %{}

  defp tracked_item_card(assigns) do
    item_data = assigns.item.item
    item_images = Map.get(assigns.images, item_data.id, %{})
    backdrop = item_images[:backdrop] || item_images[:poster]
    logo = item_images[:logo]

    assigns =
      assigns
      |> assign(:item_id, item_data.id)
      |> assign(:backdrop, backdrop)
      |> assign(:logo, logo)
      |> assign(:name, item_data.name)
      |> assign(:media_type, item_data.media_type)
      |> assign(:status_text, assigns.item.status_text)

    ~H"""
    <div
      data-nav-item
      data-entity-id={@item_id}
      tabindex="0"
      phx-click="stop_tracking"
      phx-value-item-id={@item_id}
      class="relative rounded-lg overflow-hidden glass-inset group outline-none cursor-pointer"
    >
      <div class="aspect-video relative">
        <img
          :if={@backdrop}
          src={@backdrop}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div :if={!@backdrop} class="w-full h-full flex items-center justify-center bg-base-300">
          <.icon name="hero-film" class="size-8 text-base-content/15" />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/30 via-40% to-transparent" />
        <div class="absolute bottom-2 left-2 right-2 space-y-0.5">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-8 max-w-[65%] object-contain drop-shadow-[0_1px_6px_rgba(0,0,0,0.7)]"
          />
          <p
            :if={!@logo}
            class="text-sm font-bold text-white drop-shadow-[0_1px_4px_rgba(0,0,0,0.7)] leading-tight truncate"
          >
            {@name}
          </p>
          <p class="text-[11px] text-base-content/60 drop-shadow">{@status_text}</p>
        </div>
        <div class="absolute top-1.5 right-1.5">
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

  # --- Stop tracking confirmation modal ---

  attr :item, :any, default: nil

  defp stop_tracking_modal(%{item: nil} = assigns) do
    ~H"""
    """
  end

  defp stop_tracking_modal(assigns) do
    ~H"""
    <div
      class="modal-backdrop"
      data-state="open"
      data-detail-mode="modal"
      data-dismiss-event="cancel_stop_tracking"
      style="z-index: 60;"
    >
      <div class="modal-panel modal-panel-sm p-6" phx-click-away="cancel_stop_tracking">
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
    """
  end

  # --- Calendar helpers ---

  @weekdays_attr @weekdays
  def weekdays, do: @weekdays_attr

  defp calendar_weeks(year, month) do
    first = Date.new!(year, month, 1)
    start_pad = Date.day_of_week(first) - 1
    start = Date.add(first, -start_pad)

    Enum.map(0..5, fn week ->
      Enum.map(0..6, fn day ->
        Date.add(start, week * 7 + day)
      end)
    end)
    |> Enum.reject(fn week -> Enum.all?(week, &(&1.month != month)) end)
  end

  # Build unique tracked items with a status summary for each
  defp build_tracked_items(all_releases) do
    all_releases
    |> Enum.group_by(& &1.item_id)
    |> Enum.map(fn {_item_id, releases} ->
      item = hd(releases).item
      upcoming_count = Enum.count(releases, &(not &1.released))
      released_count = Enum.count(releases, & &1.released)

      status_text =
        case {upcoming_count, released_count} do
          {0, 0} -> "tracking"
          {u, 0} -> "#{u} upcoming"
          {0, r} -> "#{r} released"
          {u, r} -> "#{u} upcoming, #{r} released"
        end

      %{item: item, status_text: status_text}
    end)
    |> Enum.sort_by(& &1.item.name)
  end

  defp releases_by_date(releases) do
    releases
    |> Enum.filter(& &1.air_date)
    |> Enum.group_by(& &1.air_date)
  end

  defp event_label(%{event_type: :began_tracking}), do: "began tracking"
  defp event_label(%{event_type: :stopped_tracking}), do: "stopped tracking"
  defp event_label(event), do: event.description

  # --- Format helpers ---

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_date()
    |> Calendar.strftime("%B %-d, %Y")
  end
end
