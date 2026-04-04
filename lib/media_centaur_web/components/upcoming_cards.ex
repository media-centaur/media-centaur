defmodule MediaCentaurWeb.Components.UpcomingCards do
  @moduledoc """
  Components for the Upcoming releases zone.
  """
  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents

  attr :releases, :map, required: true
  attr :events, :list, required: true
  attr :images, :map, default: %{}
  attr :scanning, :boolean, default: false

  def upcoming_zone(assigns) do
    watching_items = extract_watching_items(assigns.releases.upcoming)
    movie_items = Enum.filter(watching_items, &(&1.item.media_type == :movie))
    tv_items = Enum.filter(watching_items, &(&1.item.media_type == :tv_series))
    with_date = Enum.reject(assigns.releases.upcoming, &is_nil(&1.air_date))
    no_date = Enum.filter(assigns.releases.upcoming, &is_nil(&1.air_date))
    grouped_with_date = group_by_date(with_date)

    assigns =
      assigns
      |> assign(:released, assigns.releases.released)
      |> assign(:grouped, grouped_with_date)
      |> assign(:no_date, no_date)
      |> assign(:movie_items, movie_items)
      |> assign(:tv_items, tv_items)

    ~H"""
    <div class="space-y-8">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Upcoming Releases</h2>
        <button
          phx-click="scan_library"
          class="btn btn-soft btn-primary btn-sm"
          disabled={@scanning}
        >
          <.icon name="hero-magnifying-glass-mini" class="size-4" />
          {if @scanning, do: "Scanning…", else: "Scan Library"}
        </button>
      </div>

      <.released_section :if={@released != []} releases={@released} images={@images} />

      <.tracking_cards
        :if={@movie_items != [] || @tv_items != []}
        movie_items={@movie_items}
        tv_items={@tv_items}
        images={@images}
      />

      <.timeline
        :if={@grouped != [] || @no_date != []}
        grouped={@grouped}
        no_date={@no_date}
      />

      <.events_section :if={@events != []} events={@events} />

      <div
        :if={@movie_items == [] && @tv_items == [] && @released == []}
        class="text-center py-12 text-base-content/40"
      >
        <.icon name="hero-calendar-mini" class="size-8 mx-auto mb-2" />
        <p>No upcoming releases tracked</p>
        <p class="text-sm">Click "Scan Library" to find shows and movies with upcoming content</p>
      </div>
    </div>
    """
  end

  # --- Released section ---

  attr :releases, :list, required: true
  attr :images, :map, default: %{}

  defp released_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <h3 class="text-sm font-medium text-success uppercase tracking-wider">Recently Released</h3>
      <div class="space-y-2">
        <div
          :for={release <- @releases}
          class="flex items-center gap-3 text-sm py-1"
        >
          <span class="text-base-content/40 min-w-[6rem]">{format_date(release.air_date)}</span>
          <span class="font-medium">{release.item.name}</span>
          <span :if={release.title} class="text-base-content/40">— {release.title}</span>
        </div>
      </div>
    </div>
    """
  end

  # --- Tracking cards (visual summary) ---

  attr :movie_items, :list, required: true
  attr :tv_items, :list, required: true
  attr :images, :map, default: %{}

  defp tracking_cards(assigns) do
    all_items = assigns.tv_items ++ assigns.movie_items

    assigns = assign(assigns, :all_items, all_items)

    ~H"""
    <div class="grid grid-cols-[repeat(auto-fill,minmax(280px,1fr))] gap-4">
      <.tracking_card :for={entry <- @all_items} entry={entry} images={@images} />
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :images, :map, default: %{}

  defp tracking_card(assigns) do
    item = assigns.entry.item
    release = assigns.entry.release
    images = Map.get(assigns.images, item.id, %{})
    backdrop = images[:backdrop] || images[:poster]
    logo = images[:logo]

    subtitle =
      case item.media_type do
        :tv_series -> format_next_episode_short(release)
        :movie -> if(release && release.air_date, do: format_date(release.air_date), else: "TBA")
      end

    assigns =
      assigns
      |> assign(:backdrop, backdrop)
      |> assign(:logo, logo)
      |> assign(:name, item.name)
      |> assign(:subtitle, subtitle)
      |> assign(:media_type, item.media_type)

    ~H"""
    <div class="relative rounded-lg overflow-hidden glass-inset">
      <div class="aspect-video relative">
        <img
          :if={@backdrop}
          src={@backdrop}
          class="w-full h-full object-cover"
          loading="lazy"
        />
        <div :if={!@backdrop} class="w-full h-full flex items-center justify-center bg-base-300">
          <.icon name="hero-film" class="size-10 text-base-content/15" />
        </div>

        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/35 via-40% to-transparent" />

        <div class="absolute bottom-3 left-3 right-3 space-y-1">
          <img
            :if={@logo}
            src={@logo}
            class="max-h-10 max-w-[70%] object-contain drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
          />
          <h3
            :if={!@logo}
            class="text-base font-bold text-white drop-shadow-[0_2px_6px_rgba(0,0,0,0.7)] leading-tight"
          >
            {@name}
          </h3>
          <p class="text-xs text-base-content/70 drop-shadow">
            {@subtitle}
          </p>
        </div>

        <div class="absolute top-2 right-2">
          <span class={[
            "text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded",
            "bg-black/40 backdrop-blur-sm",
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

  # --- Timeline (chronological list) ---

  attr :grouped, :list, required: true
  attr :no_date, :list, required: true

  defp timeline(assigns) do
    ~H"""
    <div class="space-y-5">
      <h3 class="text-sm font-medium text-base-content/50 uppercase tracking-wider">Timeline</h3>
      <div :for={{date, releases} <- @grouped} class="space-y-1.5">
        <h4 class="text-sm font-semibold text-base-content/70 border-b border-base-content/10 pb-1">
          {format_date(date)}
        </h4>
        <div :for={release <- releases} class="flex items-baseline gap-2 text-sm pl-3 py-0.5">
          <span class="font-medium">{release.item.name}</span>
          <span :if={release.season_number} class="text-base-content/50">
            S{release.season_number}E{release.episode_number}
          </span>
          <span :if={release.title} class="text-base-content/40">"{release.title}"</span>
        </div>
      </div>
      <div :if={@no_date != []} class="space-y-1.5">
        <h4 class="text-sm font-semibold text-base-content/40 border-b border-base-content/10 pb-1">
          Release date unknown
        </h4>
        <div :for={release <- @no_date} class="flex items-baseline gap-2 text-sm pl-3 py-0.5">
          <span class="font-medium">{release.item.name}</span>
          <span :if={release.season_number} class="text-base-content/50">
            S{release.season_number}E{release.episode_number}
          </span>
          <span :if={release.title} class="text-base-content/40">"{release.title}"</span>
        </div>
      </div>
    </div>
    """
  end

  # --- Events section ---

  attr :events, :list, required: true

  defp events_section(assigns) do
    ~H"""
    <details class="collapse collapse-arrow bg-base-200/30 rounded-box">
      <summary class="collapse-title text-sm font-medium min-h-0 py-2 text-base-content/50">
        Recent Changes
      </summary>
      <div class="collapse-content space-y-1.5 pt-1">
        <div :for={event <- @events} class="flex items-baseline gap-2 text-sm text-base-content/60">
          <span class="text-base-content/30 min-w-[5rem]">{format_datetime(event.inserted_at)}</span>
          <span class="font-medium">{event.item.name}</span>
          <span class="text-base-content/40">— {event.description}</span>
        </div>
      </div>
    </details>
    """
  end

  # --- Helpers ---

  defp group_by_date(releases) do
    releases
    |> Enum.group_by(& &1.air_date)
    |> Enum.sort_by(fn {date, _} -> date end, Date)
  end

  defp extract_watching_items(releases) do
    releases
    |> Enum.uniq_by(& &1.item_id)
    |> Enum.map(fn release ->
      %{item: release.item, release: release}
    end)
  end

  defp format_next_episode_short(nil), do: "No date announced"

  defp format_next_episode_short(release) do
    date_str = if release.air_date, do: format_date(release.air_date), else: "date unknown"
    "S#{release.season_number}E#{release.episode_number} — #{date_str}"
  end

  defp format_date(nil), do: "TBA"

  defp format_date(date) do
    Calendar.strftime(date, "%B %-d, %Y")
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_date()
    |> format_date()
  end
end
