defmodule MediaCentaurWeb.Components.ReleaseTracking.TitleModal do
  @moduledoc """
  The per-title depth surface — a centered modal through the house
  `<.modal>` seam (UIDR-017), replacing the app's only slide-over so
  Incoming's two zoom-in gestures (torrent row → pursuit modal, shelf
  row → this) share one physics.

  Always in the DOM, toggled via `open`; the host LiveView drives it
  off the `?title=<item_id>` URL param (the same idiom as the pursuit
  modal's `?selected=`). Content, top to bottom: backdrop-art identity
  header, the featured next release (or a plain absence statement —
  the surface never renders empty for stragglers), the auto-grab
  toggle (hidden when acquisition isn't configured), the release
  timeline, recent activity, and the only error-tinted control on the
  page: Stop tracking.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.ReleaseTracking.EventCard, only: [event_card: 1]
  import MediaCentaurWeb.Components.Modal, only: [modal: 1]
  import MediaCentaurWeb.CoreComponents

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.ReleaseTracking.Detail
  alias MediaCentaurWeb.Components.ReleaseTracking.Present

  attr :open, :boolean, required: true
  attr :detail, Detail, default: nil, doc: "The title's detail view-model; nil while closed."
  attr :today, Date, required: true

  def title_modal(assigns) do
    assigns =
      assign(assigns, :next_event, assigns.detail && next_event(assigns.detail.timeline, assigns.today))

    ~H"""
    <.modal
      id="title-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close="close_detail"
      panel_class="max-w-[680px]"
      data-detail-mode={@open && "modal"}
      data-dismiss-event="close_detail"
    >
      <div :if={@detail} class="flex max-h-full flex-col">
        <div class="relative shrink-0 overflow-hidden p-5 pb-4">
          <%!-- The title's cached backdrop (tracking's own image store) as
                the identity header — the same treatment the pursuit modal
                and entity detail wear; the flat header remains the
                no-artwork state. --%>
          <img
            :if={@detail.backdrop_path}
            src={MediaCentaur.Library.Image.web_path(@detail.backdrop_path)}
            alt=""
            aria-hidden="true"
            class="pointer-events-none absolute inset-0 h-full w-full object-cover opacity-40"
            loading="eager"
            decoding="sync"
          />
          <div
            :if={@detail.backdrop_path}
            aria-hidden="true"
            class="pointer-events-none absolute inset-0 image-scrim-t"
          >
          </div>
          <div class="relative flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-xs uppercase tracking-wider text-base-content/40">
                <.icon name={media_icon(@detail.media_type)} class="size-4" />
                <span>{media_label(@detail.media_type)}</span>
              </div>
              <h2 class="mt-1 truncate text-xl font-bold leading-tight text-on-image-lg">
                {@detail.name}
              </h2>
              <p
                :if={@detail.tracking_since}
                class="mt-0.5 text-xs text-base-content/50 text-on-image"
              >
                Tracking since {tracking_since_label(@detail.tracking_since)}
              </p>
            </div>
            <button
              type="button"
              class="relative cursor-pointer rounded p-1 text-base-content/50 hover:bg-base-content/[0.06] hover:text-base-content"
              data-nav-item
              tabindex="0"
              phx-click="close_detail"
              aria-label="Close"
            >
              <.icon name="hero-x-mark-mini" class="size-5" />
            </button>
          </div>
        </div>

        <div class="flex-1 space-y-6 overflow-y-auto thin-scrollbar p-5 pt-2">
          <%!-- The question every open answers first: what's next? For a
                straggler the same slot states the absence plainly — the
                shape stays constant, so the surface is learnable. --%>
          <section class="space-y-2">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Next release
            </h3>
            <div
              :if={@next_event}
              class="glass-inset flex items-baseline justify-between gap-3 rounded-lg px-4 py-3"
            >
              <span class="min-w-0 truncate text-base font-semibold">
                {Present.what_drops(@next_event)}
              </span>
              <span class="flex shrink-0 items-baseline gap-2 text-sm">
                <span class="text-base-content/60">
                  {Present.relative_day(@next_event.air_date, @today)}
                </span>
                <span class={[
                  "inline-flex items-center gap-1",
                  Present.tone_text_class(Present.status_tone(@next_event.status))
                ]}>
                  <.icon name={Present.status_icon(@next_event.status)} class="size-4" />
                  {Present.status_label(@next_event.status)}
                </span>
              </span>
            </div>
            <p
              :if={!@next_event}
              class="glass-inset rounded-lg px-4 py-3 text-sm text-base-content/50"
            >
              Nothing scheduled — we'll list new releases here as soon as they're announced.
            </p>
          </section>

          <section :if={@detail.acquisition?} class="space-y-2">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Automation
            </h3>
            <label class="flex items-center justify-between gap-3">
              <span class="text-sm text-base-content/80">{@detail.auto_grab.label}</span>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@detail.auto_grab.on?}
                data-nav-item
                tabindex="0"
                phx-click="toggle_auto_grab"
                phx-value-item-id={@detail.item_id}
              />
            </label>
          </section>

          <section :if={@detail.timeline != []} class="space-y-2">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Releases
            </h3>
            <div class="space-y-1">
              <.event_card
                :for={event <- @detail.timeline}
                event={event}
                today={@today}
                variant={:compact}
              />
            </div>
          </section>

          <section :if={@detail.activity != []} class="space-y-2">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Recent activity
            </h3>
            <ul class="space-y-1.5">
              <li
                :for={entry <- @detail.activity}
                class="flex items-baseline justify-between gap-3 text-sm"
              >
                <span class="text-base-content/70">{entry.text}</span>
                <span class="shrink-0 text-xs tabular-nums text-base-content/30">{entry.at}</span>
              </li>
            </ul>
          </section>
        </div>

        <div class="shrink-0 border-t border-base-content/10 p-5 py-4">
          <button
            type="button"
            class="inline-flex cursor-pointer items-center gap-1.5 text-sm text-error/80 hover:text-error"
            data-nav-item
            tabindex="0"
            phx-click="stop_tracking"
            phx-value-item-id={@detail.item_id}
          >
            <.icon name="hero-x-circle-mini" class="size-4" />
            <span>Stop tracking</span>
          </button>
        </div>
      </div>
    </.modal>
    """
  end

  @doc """
  The featured "what's next" pick: the first timeline event dated today
  or later that hasn't already landed. `nil` when nothing lies ahead —
  the modal states the absence instead.
  """
  @spec next_event([Event.t()], Date.t()) :: Event.t() | nil
  def next_event(timeline, today) do
    Enum.find(timeline, fn %Event{} = event ->
      event.status != :in_library and event.air_date != nil and
        Date.compare(event.air_date, today) != :lt
    end)
  end

  defp tracking_since_label(datetime), do: Calendar.strftime(datetime, "%b %Y")

  defp media_icon(:tv_series), do: "hero-tv"
  defp media_icon(:movie), do: "hero-film"

  defp media_label(:tv_series), do: "TV series"
  defp media_label(:movie), do: "Movie"
end
