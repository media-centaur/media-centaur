defmodule MediaCentaurWeb.Components.Upcoming.TitleDetail do
  @moduledoc """
  The per-title detail slide-over — the "thing-first" depth behind the
  time-first rail. Carries the title's automation posture (an honest auto-grab
  toggle, hidden when acquisition isn't configured), its release timeline (the
  same event cards, compact), recent per-title activity, and the only
  error-tinted control on the page: Stop tracking.

  Enters from the right over a dimming scrim; on a wide screen it occludes the
  mini-month (the right edge is either "the month" or "one title", never both).

  Named `title_detail` rather than `detail_panel` so it does not collide with the
  existing `Components.DetailPanel` in storybook-coverage basename matching.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents
  import MediaCentaurWeb.Components.Upcoming.EventCard, only: [event_card: 1]

  alias MediaCentaurWeb.Components.Upcoming.Detail

  attr :detail, Detail, required: true, doc: "The title's detail view-model."
  attr :today, Date, required: true

  def title_detail(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50" data-detail-mode="modal" data-dismiss-event="close_detail">
      <div class="absolute inset-0 bg-black/40" phx-click="close_detail"></div>

      <div class="absolute right-0 top-0 flex h-full w-[440px] max-w-full flex-col glass-nav shadow-2xl">
        <div class="flex items-start justify-between gap-3 border-b border-base-content/10 p-5">
          <div class="min-w-0">
            <div class="flex items-center gap-2 text-xs uppercase tracking-wider text-base-content/40">
              <.icon name={media_icon(@detail.media_type)} class="size-4" />
              <span>{media_label(@detail.media_type)}</span>
            </div>
            <h2 class="mt-1 truncate text-lg font-bold leading-tight">{@detail.name}</h2>
          </div>
          <button
            type="button"
            class="rounded p-1 text-base-content/50 hover:bg-base-content/[0.06] hover:text-base-content"
            data-nav-item
            tabindex="0"
            phx-click="close_detail"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>
        </div>

        <div class="flex-1 space-y-6 overflow-y-auto p-5">
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

          <section class="space-y-2">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
              Releases
            </h3>
            <div :if={@detail.timeline != []} class="space-y-1">
              <.event_card
                :for={event <- @detail.timeline}
                event={event}
                today={@today}
                variant={:compact}
              />
            </div>
            <p :if={@detail.timeline == []} class="text-sm text-base-content/40">
              No upcoming releases.
            </p>
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

        <div class="border-t border-base-content/10 p-5">
          <button
            type="button"
            class="inline-flex items-center gap-1.5 text-sm text-error/80 hover:text-error"
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
    </div>
    """
  end

  defp media_icon(:tv_series), do: "hero-tv"
  defp media_icon(:movie), do: "hero-film"

  defp media_label(:tv_series), do: "TV series"
  defp media_label(:movie), do: "Movie"
end
