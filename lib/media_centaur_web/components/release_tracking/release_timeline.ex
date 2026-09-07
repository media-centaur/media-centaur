defmodule MediaCentaurWeb.Components.ReleaseTracking.ReleaseTimeline do
  @moduledoc """
  A tracked title's release timeline — one of the two components every
  title surface mounts (UIDR-035), so a title's calendar reads the same
  in the title detail modal and, from Phase 3, in the library detail.

  Two sections. First the featured next release, the question every
  open answers first; when nothing lies ahead the same slot states the
  absence plainly, so the shape stays constant. Then the full dated
  list, nearness-first, landed entries keeping their success label.
  Rows are not click targets — the surface already is the title — with
  one exception: the under-pursuit status is a deep-link to that
  pursuit on Incoming (the closure/handoff beat). Colour is reserved
  for status (`Present.status_tone/1`).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.ReleaseTracking.Present

  attr :id, :string, default: "release-timeline"

  attr :timeline, :list,
    required: true,
    doc: "`UpcomingFeed.Event`s nearness-first, undated last — `TrackingDetail.timeline`."

  attr :today, Date, required: true

  def release_timeline(assigns) do
    assigns = assign(assigns, :next_event, next_event(assigns.timeline, assigns.today))

    ~H"""
    <div id={@id} class="space-y-6" data-component="release-timeline">
      <section class="space-y-2">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          Next release
        </h3>
        <div
          :if={@next_event}
          id={"#{@id}-next"}
          class="glass-inset flex items-baseline justify-between gap-3 rounded-lg px-4 py-3"
        >
          <span class="min-w-0 truncate text-base font-semibold">
            {Present.what_drops(@next_event)}
          </span>
          <span class="flex shrink-0 items-baseline gap-2 text-sm">
            <span class="text-base-content/60">
              {Present.relative_day(@next_event.air_date, @today)}
            </span>
            <.status event={@next_event} />
          </span>
        </div>
        <p
          :if={!@next_event}
          id={"#{@id}-none"}
          class="glass-inset rounded-lg px-4 py-3 text-sm text-base-content/55"
        >
          Nothing scheduled — new releases are listed here as soon as they are announced.
        </p>
      </section>

      <section :if={@timeline != []} class="space-y-2">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          Releases
        </h3>
        <ul class="space-y-1">
          <li
            :for={event <- @timeline}
            id={"#{@id}-#{event.id}"}
            class="flex items-center gap-3 rounded-lg px-3 py-2"
            data-event-status={event.status}
          >
            <div class="min-w-0 flex-1">
              <div class="truncate text-sm font-medium">{Present.what_drops(event)}</div>
              <div :if={event.title} class="truncate text-xs text-base-content/55">
                {event.title}
              </div>
            </div>
            <div class="flex shrink-0 flex-col items-end gap-0.5 text-right">
              <span :if={event.air_date} class="text-xs tabular-nums text-base-content/60">
                {Present.relative_day(event.air_date, @today)}
              </span>
              <.status event={event} />
            </div>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  attr :event, Event, required: true

  # Under-pursuit is the only interactive status — a deep-link to the
  # pursuit on Incoming, the same object's other zoom level.
  defp status(%{event: %Event{status: :under_pursuit}} = assigns) do
    ~H"""
    <.link
      navigate={"/incoming?selected=#{@event.pursuit_id}"}
      class="inline-flex items-center gap-1 text-sm text-info hover:underline"
    >
      <.icon name="hero-arrow-down-tray-mini" class="size-4" />
      <span>{Present.status_label(@event.status)}</span>
      <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5 opacity-70" />
    </.link>
    """
  end

  defp status(assigns) do
    ~H"""
    <span class="inline-flex flex-col items-end gap-0.5">
      <span class={[
        "inline-flex items-center gap-1 text-sm",
        Present.tone_text_class(Present.status_tone(@event.status))
      ]}>
        <.icon name={Present.status_icon(@event.status)} class="size-4" />
        <span>{Present.status_label(@event.status)}</span>
      </span>
      <span :if={Present.theatrical_note?(@event)} class="text-[11px] text-base-content/55">
        we'll grab the digital release
      </span>
    </span>
    """
  end

  @doc """
  The featured "what's next" pick: the first timeline event dated today
  or later that hasn't already landed. `nil` when nothing lies ahead —
  the timeline states the absence instead.
  """
  @spec next_event([Event.t()], Date.t()) :: Event.t() | nil
  def next_event(timeline, today) do
    Enum.find(timeline, fn %Event{} = event ->
      event.status != :in_library and event.air_date != nil and
        Date.compare(event.air_date, today) != :lt
    end)
  end
end
