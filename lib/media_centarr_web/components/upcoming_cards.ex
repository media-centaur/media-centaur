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
  attr :queue_items, :list, default: []
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
              <.button
                variant="dismiss"
                size="sm"
                shape="square"
                phx-click="prev_month"
                tabindex="-1"
              >
                <.icon name="hero-chevron-left-mini" class="size-5" />
              </.button>
              <h2 class="text-lg font-semibold min-w-[10rem] text-center">{@month_label}</h2>
              <.button
                variant="dismiss"
                size="sm"
                shape="square"
                phx-click="next_month"
                tabindex="-1"
              >
                <.icon name="hero-chevron-right-mini" class="size-5" />
              </.button>
              <.button
                variant="dismiss"
                size="xs"
                class="ml-2 text-base-content/50"
                phx-click="jump_today"
                tabindex="-1"
              >
                Today
              </.button>
            </div>
            <.button
              :if={@tmdb_ready}
              variant="secondary"
              size="sm"
              phx-click={JS.push("open_track_modal") |> JS.focus(to: "#track-search-input")}
              tabindex="-1"
            >
              <.icon name="hero-plus-mini" class="size-4" /> Track New Releases
            </.button>
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
            queue_items={@queue_items}
            acquisition_ready={@acquisition_ready}
          />
        </div>

        <%!-- Active shows: a card per show with recent releases + next-up
        episodes folded together. Replaces the older split between Now
        Available and Upcoming — those were two views of the same data. --%>
        <div
          data-nav-item
          data-section-type="active-shows"
          tabindex="0"
          class="lg:col-span-2 space-y-3 rounded-xl outline-none p-4 glass-inset"
        >
          <h3 class="text-sm font-medium text-success uppercase tracking-wider">Active</h3>
          <%= if @released != [] or @dated_upcoming != [] do %>
            <.active_shows
              released={@released}
              upcoming={@dated_upcoming}
              grab_statuses={@grab_statuses}
              queue_items={@queue_items}
              acquisition_ready={@acquisition_ready}
              images={@images}
            />
          <% else %>
            <p class="text-sm text-base-content/50">
              Nothing happening right now. Tracked shows with future episodes appear here.
            </p>
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
              <div :for={event <- @events} class="release-row">
                <span class="text-base-content/30 tabular-nums text-right">
                  {format_datetime(event.inserted_at)}
                </span>
                <span class="font-medium">{event.item_name}</span>
                <span class="text-base-content/40 col-span-2">
                  {event_label(event)}
                </span>
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
  attr :queue_items, :list, default: []
  attr :acquisition_ready, :boolean, default: false

  defp day_detail(assigns) do
    ~H"""
    <div class="rounded-xl border border-primary/20 bg-base-200/30 p-4 space-y-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold">
          {Calendar.strftime(@day, "%A, %B %-d")}
        </h3>
        <.button variant="dismiss" size="xs" shape="square" phx-click="select_day" phx-value-date="">
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.button>
      </div>
      <div class="grid grid-cols-[repeat(auto-fill,minmax(240px,360px))] gap-3">
        <.day_release_card
          :for={release <- @releases}
          release={release}
          images={@images}
          grab_statuses={@grab_statuses}
          queue_items={@queue_items}
          acquisition_ready={@acquisition_ready}
        />
      </div>
    </div>
    """
  end

  attr :release, :any, required: true
  attr :images, :map, default: %{}
  attr :grab_statuses, :map, default: %{}
  attr :queue_items, :list, default: []
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

    status =
      if assigns.acquisition_ready do
        grab = lookup_grab(assigns.release, assigns.grab_statuses)
        queue_item = lookup_queue_item(assigns.release, assigns.queue_items)
        release_status(assigns.release.in_library, grab, queue_item)
      else
        :none
      end

    assigns =
      assign(assigns, :destination, row_destination(assigns.release, status, assigns.acquisition_ready))

    ~H"""
    <.link
      navigate={@destination}
      class={[
        "block relative rounded-lg overflow-hidden glass-inset hover:ring-1 hover:ring-primary/40 transition-all",
        @is_released && "opacity-60"
      ]}
    >
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
          <.release_status_icon
            release={@release}
            grab_statuses={@grab_statuses}
            queue_items={@queue_items}
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
    </.link>
    """
  end

  # --- Active shows: card per show with recent + upcoming episodes ---
  #
  # Replaces the older split between Now Available and Upcoming. One
  # card per show — released rows on top with status icons, upcoming
  # rows below capped at 3 with "+N more" so the card stays compact.
  # Long-tail upcoming dates are still on the Calendar.

  @upcoming_visible_per_card 3

  attr :released, :list, required: true
  attr :upcoming, :list, required: true
  attr :grab_statuses, :map, default: %{}
  attr :queue_items, :list, default: []
  attr :acquisition_ready, :boolean, default: false
  attr :images, :map, default: %{}

  defp active_shows(assigns) do
    groups = merge_active_groups(assigns.released, assigns.upcoming)
    assigns = assign(assigns, :groups, groups)

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
      <.active_card
        :for={group <- @groups}
        item={group.item}
        released={group.released}
        upcoming={group.upcoming}
        upcoming_overflow={group.upcoming_overflow}
        images={@images}
        grab_statuses={@grab_statuses}
        queue_items={@queue_items}
        acquisition_ready={@acquisition_ready}
      />
    </div>
    """
  end

  @doc """
  Merges the released and upcoming buckets into per-show groups. Each
  group carries its released releases (sorted by season/episode), the
  next `@upcoming_visible_per_card` upcoming releases, and an overflow
  count for the "+N more" indicator.

  Public so the unit test can exercise the cap and sort behaviour
  directly without going through render.
  """
  @spec merge_active_groups([map()], [map()]) :: [
          %{
            item: map(),
            released: [map()],
            upcoming: [map()],
            upcoming_overflow: non_neg_integer()
          }
        ]
  def merge_active_groups(released, upcoming) do
    released_by_item = Enum.group_by(released, & &1.item_id)
    upcoming_by_item = Enum.group_by(upcoming, & &1.item_id)

    item_ids = Enum.uniq(Map.keys(released_by_item) ++ Map.keys(upcoming_by_item))

    items_lookup = Map.new(released ++ upcoming, &{&1.item_id, &1.item})

    item_ids
    |> Enum.map(fn item_id ->
      released_releases =
        released_by_item
        |> Map.get(item_id, [])
        |> Enum.sort_by(&{&1.season_number || 0, &1.episode_number || 0})

      all_upcoming =
        upcoming_by_item
        |> Map.get(item_id, [])
        |> Enum.sort_by(&(&1.air_date || ~D[9999-12-31]), Date)

      visible_upcoming = Enum.take(all_upcoming, @upcoming_visible_per_card)
      overflow = max(length(all_upcoming) - @upcoming_visible_per_card, 0)

      %{
        item: Map.fetch!(items_lookup, item_id),
        released: released_releases,
        upcoming: visible_upcoming,
        upcoming_overflow: overflow
      }
    end)
    |> Enum.sort_by(&group_activity_key/1, :desc)
  end

  # Sort key per group, returned as an integer so `:desc` sort uses
  # numeric comparison (Date structs don't sort chronologically under
  # Erlang's default term order).
  #
  # - Released groups: `+days_since_year_one(max_date)` — bigger means
  #   more recent, sorts first under `:desc`.
  # - Upcoming-only groups: `-days_since_year_one(min_date)` — negative
  #   so they sort BELOW released groups; the bigger value (closer to
  #   zero) corresponds to the soonest date.
  # - Empty groups (no released, no upcoming): far negative sentinel.
  defp group_activity_key(%{released: released, upcoming: upcoming}) do
    released_dates = Enum.reject(Enum.map(released, & &1.air_date), &is_nil/1)
    upcoming_dates = Enum.reject(Enum.map(upcoming, & &1.air_date), &is_nil/1)

    case {released_dates, upcoming_dates} do
      {[], []} ->
        -1_000_000_000

      {[], dates} ->
        -Date.diff(Enum.min(dates, Date), ~D[0001-01-01])

      {dates, _} ->
        Date.diff(Enum.max(dates, Date), ~D[0001-01-01])
    end
  end

  attr :item, :map, required: true
  attr :released, :list, required: true
  attr :upcoming, :list, default: []
  attr :upcoming_overflow, :integer, default: 0
  attr :images, :map, default: %{}
  attr :grab_statuses, :map, default: %{}
  attr :queue_items, :list, default: []
  attr :acquisition_ready, :boolean, default: false

  defp active_card(assigns) do
    item_images = Map.get(assigns.images, assigns.item.id, %{})
    backdrop = item_images[:backdrop] || item_images[:poster]

    # Card kind decided by what's actually being rendered. If there are
    # released movie rows, prefer streaming/theatrical decision over
    # falling back to upcoming. Otherwise (TV or upcoming-only movie)
    # use the released list, then upcoming as a fallback.
    seed = first_present(assigns.released, assigns.upcoming)
    {kind, single_release} = card_kind(assigns.item, seed)

    # A whole-card click only makes sense for streaming-movie cards
    # (single actionable release). TV cards have per-row clicks; theatrical
    # cards are informational with no destination.
    card_destination =
      case {kind, single_release} do
        {:movie_streaming, release} ->
          status =
            if assigns.acquisition_ready do
              grab = lookup_grab(release, assigns.grab_statuses)
              queue_item = lookup_queue_item(release, assigns.queue_items)
              release_status(release.in_library, grab, queue_item)
            else
              :none
            end

          row_destination(release, status, assigns.acquisition_ready)

        _ ->
          nil
      end

    assigns =
      assigns
      |> assign(backdrop: backdrop)
      |> assign(kind: kind)
      |> assign(card_destination: card_destination)

    ~H"""
    <%= if @card_destination do %>
      <.link
        navigate={@card_destination}
        class="block hover:ring-1 hover:ring-primary/40 rounded-lg transition-all"
      >
        <.active_card_inner
          item={@item}
          released={@released}
          upcoming={@upcoming}
          upcoming_overflow={@upcoming_overflow}
          backdrop={@backdrop}
          kind={@kind}
          grab_statuses={@grab_statuses}
          queue_items={@queue_items}
          acquisition_ready={@acquisition_ready}
        />
      </.link>
    <% else %>
      <.active_card_inner
        item={@item}
        released={@released}
        upcoming={@upcoming}
        upcoming_overflow={@upcoming_overflow}
        backdrop={@backdrop}
        kind={@kind}
        grab_statuses={@grab_statuses}
        queue_items={@queue_items}
        acquisition_ready={@acquisition_ready}
      />
    <% end %>
    """
  end

  defp first_present([_ | _] = a, _b), do: a
  defp first_present([], b), do: b

  attr :item, :map, required: true
  attr :released, :list, required: true
  attr :upcoming, :list, default: []
  attr :upcoming_overflow, :integer, default: 0
  attr :backdrop, :string, default: nil
  attr :kind, :atom, required: true
  attr :grab_statuses, :map, default: %{}
  attr :queue_items, :list, default: []
  attr :acquisition_ready, :boolean, default: false

  defp active_card_inner(assigns) do
    pending_count =
      if assigns.acquisition_ready,
        do: pending_grab_count(assigns.released, assigns.grab_statuses),
        else: 0

    home_lines =
      case assigns.kind do
        :theatrical ->
          home_release_lines(build_home_release_summary(assigns.released ++ assigns.upcoming))

        _ ->
          []
      end

    assigns =
      assigns
      |> assign(:pending_count, pending_count)
      |> assign(:home_lines, home_lines)

    ~H"""
    <div class="rounded-lg overflow-hidden glass-inset">
      <%!-- Backdrop header --%>
      <div class="relative aspect-[21/9]">
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
        <div class="absolute bottom-2 left-2 right-2 flex items-end justify-between gap-2">
          <p class="text-sm font-bold text-white drop-shadow-[0_1px_4px_rgba(0,0,0,0.7)] leading-tight truncate">
            {@item.name}
          </p>
          <.kind_badge kind={@kind} />
        </div>
      </div>

      <%!-- Body: released rows on top, upcoming rows below.
           For movies, the single-release card has a different shape. --%>
      <%= case @kind do %>
        <% :tv -> %>
          <div class="px-3 py-2 space-y-0.5">
            <div :if={@released != []} class="release-grid text-sm">
              <.active_episode_row
                :for={release <- @released}
                release={release}
                grab_statuses={@grab_statuses}
                queue_items={@queue_items}
                acquisition_ready={@acquisition_ready}
              />
            </div>
            <div
              :if={@pending_count >= 2}
              class="flex justify-end pt-1"
            >
              <.button
                variant="secondary"
                size="xs"
                phx-click="queue_all_show"
                phx-value-item-id={@item.id}
                aria-label={"Queue all #{@pending_count} pending episodes"}
                tabindex="-1"
              >
                <.icon name="hero-arrow-down-tray-mini" class="size-3.5" /> Queue all {@pending_count}
              </.button>
            </div>
            <div
              :if={@released != [] and @upcoming != []}
              class="border-t border-base-content/10 my-1"
            />
            <div :if={@upcoming != []} class="release-grid text-sm">
              <.upcoming_episode_row :for={release <- @upcoming} release={release} />
            </div>
            <p :if={@upcoming_overflow > 0} class="text-xs text-base-content/40 pl-1 pt-1">
              +{@upcoming_overflow} more on the calendar
            </p>
          </div>
        <% :movie_streaming -> %>
          <div class="px-3 py-2 flex items-center gap-2 text-sm">
            <.release_status_icon
              release={hd(seed_releases(@released, @upcoming))}
              grab_statuses={@grab_statuses}
              queue_items={@queue_items}
              acquisition_ready={@acquisition_ready}
            />
            <span class="text-base-content/60">
              {movie_streaming_label(@released, @upcoming)}
            </span>
          </div>
        <% :theatrical -> %>
          <div class="px-3 py-2 space-y-0.5">
            <div class="text-xs text-base-content/50">
              {theatrical_label(hd(seed_releases(@released, @upcoming)).air_date)}
            </div>
            <div :for={line <- @home_lines} class="text-xs text-base-content/40">
              {line}
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp seed_releases([_ | _] = released, _upcoming), do: released
  defp seed_releases([], upcoming), do: upcoming

  defp movie_streaming_label([_ | _], _upcoming), do: "Available now"

  defp movie_streaming_label([], [release | _]) do
    case release.air_date do
      nil -> "Coming soon"
      date -> "Available " <> Calendar.strftime(date, "%B %-d, %Y")
    end
  end

  defp theatrical_label(nil), do: "In theaters"

  defp theatrical_label(%Date{} = date) do
    case Date.compare(date, Date.utc_today()) do
      :gt -> "In theaters " <> Calendar.strftime(date, "%B %-d, %Y")
      _ -> "In theaters since " <> Calendar.strftime(date, "%B %-d, %Y")
    end
  end

  attr :kind, :atom, required: true

  defp kind_badge(%{kind: :tv} = assigns) do
    ~H"""
    <span class="text-[9px] font-semibold uppercase tracking-wider px-1 py-0.5 rounded bg-info/15 text-info shrink-0">
      TV
    </span>
    """
  end

  defp kind_badge(%{kind: :movie_streaming} = assigns) do
    ~H"""
    <span class="text-[9px] font-semibold uppercase tracking-wider px-1 py-0.5 rounded bg-warning/15 text-warning shrink-0">
      Streaming
    </span>
    """
  end

  defp kind_badge(%{kind: :theatrical} = assigns) do
    ~H"""
    <span class="text-[9px] font-semibold uppercase tracking-wider px-1 py-0.5 rounded bg-base-content/10 text-base-content/60 shrink-0">
      🎬 Theaters
    </span>
    """
  end

  attr :release, :map, required: true
  attr :grab_statuses, :map, default: %{}
  attr :queue_items, :list, default: []
  attr :acquisition_ready, :boolean, default: false

  defp active_episode_row(assigns) do
    status =
      if assigns.acquisition_ready do
        grab = lookup_grab(assigns.release, assigns.grab_statuses)
        queue_item = lookup_queue_item(assigns.release, assigns.queue_items)
        release_status(assigns.release.in_library, grab, queue_item)
      else
        :none
      end

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:destination, row_destination(assigns.release, status, assigns.acquisition_ready))

    ~H"""
    <.link navigate={@destination} class="release-row group hover:bg-base-content/5 rounded">
      <span class="text-base-content/30 tabular-nums text-right">
        {if @release.air_date, do: Calendar.strftime(@release.air_date, "%b %-d"), else: "—"}
      </span>
      <span class="font-medium truncate">
        <span :if={@release.season_number} class="text-base-content/50 tabular-nums mr-1">
          S{String.pad_leading("#{@release.season_number}", 2, "0")}E{String.pad_leading(
            "#{@release.episode_number}",
            2,
            "0"
          )}
        </span>
        <span :if={@release.title} class="text-base-content/70">"{@release.title}"</span>
      </span>
      <div class="flex items-center gap-1 justify-end col-span-2">
        <.release_status_icon
          release={@release}
          grab_statuses={@grab_statuses}
          queue_items={@queue_items}
          acquisition_ready={@acquisition_ready}
        />
        <.icon
          :if={@status == :none and @acquisition_ready}
          name="hero-arrow-down-tray-mini"
          class="size-3.5 text-base-content/40 opacity-0 group-hover:opacity-60 transition-opacity"
        />
      </div>
    </.link>
    """
  end

  # Upcoming row: future episode in the same card, no acquisition state
  # to show, not clickable. Just date + episode info, dimmed to differentiate
  # from released/active rows visually.
  attr :release, :map, required: true

  defp upcoming_episode_row(assigns) do
    ~H"""
    <div class="release-row text-base-content/50">
      <span class="text-base-content/30 tabular-nums text-right">
        {if @release.air_date, do: Calendar.strftime(@release.air_date, "%b %-d"), else: "—"}
      </span>
      <span class="truncate">
        <span :if={@release.season_number} class="tabular-nums mr-1 text-base-content/40">
          S{String.pad_leading("#{@release.season_number}", 2, "0")}E{String.pad_leading(
            "#{@release.episode_number}",
            2,
            "0"
          )}
        </span>
        <span :if={@release.title} class="text-base-content/50">"{@release.title}"</span>
      </span>
      <div
        class="flex items-center gap-1 justify-end col-span-2 text-base-content/30"
        title="Upcoming"
      >
        <.icon name="hero-clock-mini" class="size-3.5" />
      </div>
    </div>
    """
  end

  # Determines what shape of card to render. Returns `{kind, optional_single_release}`.
  defp card_kind(%{media_type: :tv_series}, _releases), do: {:tv, nil}

  defp card_kind(%{media_type: :movie}, releases) do
    # `Enum.split_with(releases, &(&1.release_type == "theatrical"))` partitions
    # into `{theatrical, non_theatrical}`. A streaming row (or any non-theatrical
    # row) wins because that's the downloadable surface; otherwise we fall
    # back to the theatrical row for informational display.
    case Enum.split_with(releases, &(&1.release_type == "theatrical")) do
      {_theatrical, [streaming | _]} -> {:movie_streaming, streaming}
      {[theatrical | _], []} -> {:theatrical, theatrical}
    end
  end

  # --- Upcoming list content ---

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
        <.button
          variant="dismiss"
          size="xs"
          shape="square"
          class="opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity pointer-events-none"
          tabindex="-1"
          aria-hidden="true"
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </.button>
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
            <.button
              variant="dismiss"
              size="sm"
              data-nav-item
              tabindex="0"
              phx-click="cancel_stop_tracking"
            >
              Cancel
            </.button>
            <.button
              variant="danger"
              size="sm"
              data-nav-item
              tabindex="0"
              phx-click="confirm_stop_tracking"
            >
              Stop tracking
            </.button>
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
  # Per-release acquisition state
  #
  # Each row on Now Available is wrapped in a `<.link>` whose destination
  # depends on the release's current state — see `row_destination/3`.
  # The accompanying icon (rendered by `release_status_icon/1`) gives an
  # at-a-glance visual cue without itself being clickable.
  # ---------------------------------------------------------------------------

  alias MediaCentarr.Acquisition.{Grab, QueueItem}

  @doc """
  Resolves a release's acquisition state from its library presence, the
  matching grab row (or nil), and the matching download-client queue item
  (or nil).

  Takes primitive `in_library?` rather than the full `Release` struct so
  the resolver doesn't pull `MediaCentarr.ReleaseTracking.Release` across
  the bounded-context boundary (which doesn't export it).

  Pure function — extracted for unit testing of every state combo.

  ## State precedence

  1. `:completed` — file is in library (highest precedence; once it's
     here, nothing else matters)
  2. `:downloading | :paused | :errored` — grab succeeded; live state
     comes from the queue item, defaulting to `:downloading` if no
     queue item matches (still queued or already imported)
  3. `:searching` — grab is `searching` or `snoozed`
  4. `:abandoned` — gave up after max attempts
  5. `:cancelled` — explicitly stopped (visually treated as no-op)
  6. `:none` — no grab, not in library
  """
  @spec release_status(boolean(), Grab.t() | nil, QueueItem.t() | nil) ::
          :completed
          | :downloading
          | :paused
          | :errored
          | :searching
          | :abandoned
          | :cancelled
          | :none
  def release_status(true, _grab, _queue), do: :completed

  def release_status(false, %Grab{status: "grabbed"}, %QueueItem{state: state}) do
    case state do
      :paused -> :paused
      :error -> :errored
      _ -> :downloading
    end
  end

  def release_status(false, %Grab{status: "grabbed"}, nil), do: :downloading

  def release_status(false, %Grab{status: status}, _queue) when status in ["searching", "snoozed"],
    do: :searching

  def release_status(false, %Grab{status: "abandoned"}, _queue), do: :abandoned
  def release_status(false, %Grab{status: "cancelled"}, _queue), do: :cancelled
  def release_status(false, nil, _queue), do: :none

  @doc """
  Walks a movie's release rows once and picks the earliest air_date per
  release type. Returns a struct-like map with `:theatrical`, `:digital`,
  and `:physical` keys, each `Date.t()` or `nil`.

  Multiple rows of the same type (e.g. duplicate digital entries from
  different countries) collapse to the earliest known date — deterministic
  even though we currently extract US-only.

  Pure function — used by the per-item view-model in the active-shows
  pipeline so the render layer doesn't re-derive this data on every patch.
  """
  @spec build_home_release_summary([map()]) :: %{
          theatrical: Date.t() | nil,
          digital: Date.t() | nil,
          physical: Date.t() | nil
        }
  def build_home_release_summary(releases) do
    by_type = Enum.group_by(releases, & &1.release_type)

    %{
      theatrical: earliest_air_date(Map.get(by_type, "theatrical")),
      digital: earliest_air_date(Map.get(by_type, "digital")),
      physical: earliest_air_date(Map.get(by_type, "physical"))
    }
  end

  defp earliest_air_date(nil), do: nil

  defp earliest_air_date(releases) when is_list(releases) do
    releases
    |> Enum.map(& &1.air_date)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.min(dates, Date)
    end
  end

  @doc """
  Formats a home-release summary into one or more lines of secondary text.

  Returns `[]` for non-theatrical contexts (the streaming-card path already
  shows its own date), `["Home release: not yet announced"]` when we have a
  theatrical date but no home dates yet, and one line per known home format
  otherwise.

  Pure function — pairs with `build_home_release_summary/1`.
  """
  @spec home_release_lines(%{
          theatrical: Date.t() | nil,
          digital: Date.t() | nil,
          physical: Date.t() | nil
        }) :: [String.t()]
  def home_release_lines(%{theatrical: nil}), do: []

  def home_release_lines(%{digital: nil, physical: nil}) do
    ["Home release: not yet announced"]
  end

  def home_release_lines(%{digital: digital, physical: physical}) do
    []
    |> append_home_line("Digital", digital)
    |> append_home_line("Physical", physical)
  end

  defp append_home_line(lines, _label, nil), do: lines

  defp append_home_line(lines, label, %Date{} = date) do
    lines ++ ["#{label}: #{Calendar.strftime(date, "%b %-d, %Y")}"]
  end

  @doc """
  Counts releases that should appear under the "Queue all (N)" button —
  released-but-not-grabbed episodes for which a bulk action would actually
  produce a new grab. A release is counted when it is not in the library
  and has no existing grab row of any status (terminal grabs are skipped
  because the user must explicitly re-arm them).

  Pure function — `grab_statuses` is the same map produced by
  `MediaCentarr.Acquisition.statuses_for_releases/1`.
  """
  @spec pending_grab_count([map()], map()) :: non_neg_integer()
  def pending_grab_count(releases, grab_statuses) do
    Enum.count(releases, fn release ->
      not release.in_library and is_nil(lookup_grab(release, grab_statuses))
    end)
  end

  @doc """
  Groups a flat list of releases by the show/movie they belong to.

  Returns `[%{item: item, releases: [release]}]` where:
  - releases within each group are sorted by `(season_number, episode_number)`
    ascending (so an episode list reads top-to-bottom in viewing order)
  - groups themselves are sorted by the freshest air_date in the group,
    descending (most recent activity surfaces first; nil-date groups
    sink to the bottom)

  Each release is expected to have its `:item` association preloaded.
  Pure function — no I/O, no DB.
  """
  @spec group_releases_by_item([map()]) :: [%{item: map(), releases: [map()]}]
  def group_releases_by_item(releases) do
    releases
    |> Enum.group_by(& &1.item_id)
    |> Enum.map(fn {_item_id, group_releases} ->
      first = hd(group_releases)
      sorted = Enum.sort_by(group_releases, &{&1.season_number || 0, &1.episode_number || 0})
      %{item: first.item, releases: sorted}
    end)
    |> Enum.sort_by(&group_sort_key/1, :desc)
  end

  # Sort key: latest air_date in the group. nil air_dates sink to the bottom
  # by mapping them to a sentinel that sorts as oldest-possible.
  defp group_sort_key(%{releases: releases}) do
    releases
    |> Enum.map(& &1.air_date)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ~D[0001-01-01]
      dates -> Enum.max(dates, Date)
    end
  end

  defp lookup_grab(release, grab_statuses) do
    key =
      {to_string(release.item.tmdb_id), to_string(release.item.media_type), release.season_number,
       release.episode_number}

    Map.get(grab_statuses, key)
  end

  # Fuzzy match: a torrent in the queue is considered to belong to a
  # release when its title contains the tracked item's name. Brittle but
  # workable — Prowlarr → qBittorrent doesn't preserve a stable ID we
  # could otherwise key on.
  defp lookup_queue_item(release, queue_items) do
    needle = release.item.name |> to_string() |> String.downcase()

    Enum.find(queue_items || [], fn item ->
      String.contains?(String.downcase(item.title), needle)
    end)
  end

  attr :release, :map, required: true
  attr :grab_statuses, :map, default: %{}
  attr :queue_items, :list, default: []
  attr :acquisition_ready, :boolean, default: false

  defp release_status_icon(assigns) do
    status =
      if assigns.acquisition_ready do
        grab = lookup_grab(assigns.release, assigns.grab_statuses)
        queue_item = lookup_queue_item(assigns.release, assigns.queue_items)
        release_status(assigns.release.in_library, grab, queue_item)
      else
        :none
      end

    assigns = assign(assigns, status: status)

    ~H"""
    <span
      :if={@status not in [:none, :cancelled]}
      class={["inline-flex items-center justify-center", status_color(@status)]}
      title={status_tooltip(@status)}
      aria-label={status_tooltip(@status)}
    >
      <.icon name={status_icon_name(@status)} class="size-4" />
    </span>
    """
  end

  defp status_icon_name(:completed), do: "hero-check-circle-mini"
  defp status_icon_name(:downloading), do: "hero-arrow-down-tray-mini"
  defp status_icon_name(:paused), do: "hero-pause-circle-mini"
  defp status_icon_name(:errored), do: "hero-exclamation-triangle-mini"
  defp status_icon_name(:searching), do: "hero-clock-mini"
  defp status_icon_name(:abandoned), do: "hero-exclamation-triangle-mini"

  defp status_color(:completed), do: "text-success"
  defp status_color(:downloading), do: "text-primary"
  defp status_color(:paused), do: "text-base-content/60"
  defp status_color(:errored), do: "text-warning"
  defp status_color(:searching), do: "text-info"
  defp status_color(:abandoned), do: "text-error/70"

  defp status_tooltip(:completed), do: "Completed — in library"
  defp status_tooltip(:downloading), do: "Downloading"
  defp status_tooltip(:paused), do: "Paused"
  defp status_tooltip(:errored), do: "Download error"
  defp status_tooltip(:searching), do: "Searching for a release"
  defp status_tooltip(:abandoned), do: "Couldn't find a release — re-arm in Downloads"

  @doc """
  Click destination for a release row. Splits by state:

  - `:completed` → Library entity (the user wants to play it, not look at downloads)
  - `:none` / `:searching` / `:cancelled` → Downloads page with a manual
    Prowlarr search auto-fired so the user can intervene
  - All other states → Downloads activity, filtered to the title

  The Library entity URL falls back to the manual search when the
  tracking item isn't linked to a library entity.
  """
  def row_destination(release, status, acquisition_ready) do
    cond do
      status == :completed and not is_nil(release.item.library_entity_id) ->
        "/library?selected=#{release.item.library_entity_id}"

      not acquisition_ready ->
        if release.item.library_entity_id,
          do: "/library?selected=#{release.item.library_entity_id}",
          else: "/"

      status in [:none, :searching, :cancelled] ->
        "/download?prowlarr_search=" <> URI.encode_www_form(release.item.name)

      true ->
        "/download?filter=all&search=" <> URI.encode_www_form(release.item.name)
    end
  end
end
