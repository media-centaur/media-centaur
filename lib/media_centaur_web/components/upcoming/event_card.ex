defmodule MediaCentaurWeb.Components.Upcoming.EventCard do
  @moduledoc """
  One release event on the Upcoming rail, in a `:hero` (large, proximity-scaled
  backdrop) or `:compact` (row) variant.

  Colour is reserved for status (`Present.status_tone/1`): green for armed /
  landed, blue for under-pursuit, muted amber for info-only theatrical. The
  card opens the title's detail panel; the under-pursuit status is itself a
  deep-link to that pursuit on the Downloads page (the closure/handoff beat).
  Wording and tones come from the pure `Present` helpers.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.Upcoming.Present

  attr :event, Event, required: true, doc: "The release event view-model to render."
  attr :variant, :atom, values: [:hero, :feature, :compact], default: :compact

  attr :today, Date,
    required: true,
    doc: ~s{Today's date, for the relative-day copy ("Today" / "in 3 days").}

  def event_card(%{variant: variant} = assigns) when variant in [:hero, :feature] do
    assigns =
      assigns
      |> assign(:backdrop, backdrop_src(assigns.event, 960))
      |> assign(:frame_class, if(variant == :hero, do: "aspect-[21/9]", else: "h-44"))
      |> assign(:title_class, if(variant == :hero, do: "text-xl", else: "text-lg"))

    ~H"""
    <div
      class={[
        "group relative cursor-pointer overflow-hidden rounded-xl glass-surface hover:ring-1 hover:ring-base-content/20",
        @frame_class
      ]}
      data-nav-item
      tabindex="0"
      role="button"
      data-event-status={@event.status}
      data-date={@event.air_date && Date.to_iso8601(@event.air_date)}
      phx-click="select_event"
      phx-value-item-id={@event.item_id}
    >
      <img
        :if={@backdrop}
        src={@backdrop}
        alt=""
        class="absolute inset-0 h-full w-full object-cover object-top"
        loading="eager"
        decoding="sync"
      />
      <div :if={!@backdrop} class="absolute inset-0 flex items-center justify-center bg-base-300">
        <.icon name="hero-film" class="size-10 text-base-content/20" />
      </div>
      <div class="absolute inset-0 bg-gradient-to-t from-base-100 via-base-100/40 to-transparent">
      </div>
      <div class="absolute inset-x-0 bottom-0 space-y-1 p-4">
        <div class="flex items-center gap-2 text-xs">
          <span class="font-medium uppercase tracking-wider text-base-content/80 text-on-image">
            {Present.relative_day(@event.air_date, @today)}
          </span>
          <span class="text-base-content/40">·</span>
          <span class="text-base-content/70 text-on-image">{Present.what_drops(@event)}</span>
        </div>
        <h3 class={["font-bold leading-tight text-on-image-lg", @title_class]}>{@event.item_name}</h3>
        <.status_affordance event={@event} />
      </div>
    </div>
    """
  end

  def event_card(%{variant: :compact} = assigns) do
    assigns = assign(assigns, :backdrop, backdrop_src(assigns.event, 320))

    ~H"""
    <div
      class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2 transition-colors hover:bg-base-content/[0.03]"
      data-nav-item
      tabindex="0"
      role="button"
      data-event-status={@event.status}
      data-date={@event.air_date && Date.to_iso8601(@event.air_date)}
      phx-click="select_event"
      phx-value-item-id={@event.item_id}
    >
      <div class="h-12 w-20 shrink-0 overflow-hidden rounded-md bg-base-300">
        <img
          :if={@backdrop}
          src={@backdrop}
          alt=""
          class="h-full w-full object-cover object-top"
          loading="eager"
          decoding="sync"
        />
        <div :if={!@backdrop} class="flex h-full w-full items-center justify-center">
          <.icon name="hero-film" class="size-5 text-base-content/20" />
        </div>
      </div>

      <div class="min-w-0 flex-1">
        <div class="truncate text-sm font-medium">{@event.item_name}</div>
        <div class="truncate text-xs text-base-content/50">{Present.what_drops(@event)}</div>
      </div>

      <div class="flex shrink-0 flex-col items-end gap-0.5 text-right">
        <span class="text-xs tabular-nums text-base-content/60">
          {Present.relative_day(@event.air_date, @today)}
        </span>
        <.status_affordance event={@event} />
      </div>
    </div>
    """
  end

  # Under-pursuit is the only interactive status — a deep-link to the pursuit on
  # the Downloads page. stopPropagation so it doesn't also open the detail panel.
  defp status_affordance(%{event: %{status: :under_pursuit}} = assigns) do
    ~H"""
    <.link
      navigate={"/download?selected=#{@event.pursuit_id}"}
      onclick="event.stopPropagation()"
      class="inline-flex items-center gap-1 text-sm text-info hover:underline"
    >
      <.icon name="hero-arrow-down-tray-mini" class="size-4" />
      <span>{Present.status_label(@event.status)}</span>
      <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5 opacity-70" />
    </.link>
    """
  end

  defp status_affordance(assigns) do
    ~H"""
    <span class="inline-flex flex-col items-end gap-0.5">
      <span class={[
        "inline-flex items-center gap-1 text-sm",
        Present.tone_text_class(Present.status_tone(@event.status))
      ]}>
        <.icon name={Present.status_icon(@event.status)} class="size-4" />
        <span>{Present.status_label(@event.status)}</span>
      </span>
      <span :if={Present.theatrical_note?(@event)} class="text-[11px] text-base-content/40">
        we'll grab the digital release
      </span>
    </span>
    """
  end

  defp backdrop_src(%Event{backdrop_path: nil}, _width), do: nil

  defp backdrop_src(%Event{backdrop_path: path}, width),
    do: sized_image_url("/media-images/" <> path, width)
end
