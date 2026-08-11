defmodule MediaCentaurWeb.Components.ReleaseTracking.TitleModal do
  @moduledoc """
  The per-title depth surface (UIDR-017) — a tenant of the cinematic
  modal frame, so a tracked title reads as the same surface as one in
  the library: fixed backdrop, hero window, pinned identity lockup
  (logo when the tracking cache has one, logotype fallback), with the
  tracking depth as the scrolling body.

  Always in the DOM, toggled via `open`; the host LiveView drives it
  off the `?title=<item_id>` URL param (the same idiom as the pursuit
  modal's `?selected=`). Body, top to bottom: the featured next release
  (or a plain absence statement — the surface never renders empty for
  stragglers), the auto-grab toggle (hidden when acquisition isn't
  configured), the release timeline, recent activity, and the only
  error-tinted control on the page: Stop tracking. No close-X — the
  frame's backdrop click and Escape both close, like the library detail
  modal.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.ReleaseTracking.EventCard, only: [event_card: 1]
  import MediaCentaurWeb.CoreComponents

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.CinematicShell
  alias MediaCentaurWeb.Components.Detail.TitleLayer
  alias MediaCentaurWeb.Components.ReleaseTracking.Detail
  alias MediaCentaurWeb.Components.ReleaseTracking.Present

  attr :open, :boolean, required: true
  attr :detail, Detail, default: nil, doc: "The title's detail view-model; nil while closed."
  attr :today, Date, required: true

  def title_modal(assigns) do
    assigns =
      assign(assigns, :next_event, assigns.detail && next_event(assigns.detail.timeline, assigns.today))

    ~H"""
    <CinematicShell.cinematic_shell
      id="title-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close="close_detail"
      present={@detail != nil}
      backdrop_url={@detail && @detail.backdrop_url}
      scroll_key={@detail && @detail.item_id}
      view_key={:main}
      data-detail-mode={@open && "modal"}
      data-dismiss-event="close_detail"
    >
      <:orientation>
        <div :if={@detail} class="px-6">
          <TitleLayer.lockup title={@detail.name} logo_url={@detail.logo_url} />
          <p class="mt-3 flex items-center gap-2 pb-5 text-xs uppercase tracking-wider text-base-content/50 text-on-image">
            <.icon name={media_icon(@detail.media_type)} class="size-4" />
            <span>{media_label(@detail.media_type)}</span>
            <span
              :if={@detail.tracking_since}
              class="normal-case tracking-normal text-base-content/40"
            >
              · Tracking since {tracking_since_label(@detail.tracking_since)}
            </span>
          </p>
        </div>
      </:orientation>
      <:body>
        <div :if={@detail} class="space-y-6 px-1 pt-2">
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

          <div class="border-t border-base-content/10 py-4">
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
      </:body>
    </CinematicShell.cinematic_shell>
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
