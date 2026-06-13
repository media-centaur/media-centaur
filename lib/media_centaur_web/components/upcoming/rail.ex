defmodule MediaCentaurWeb.Components.Upcoming.Rail do
  @moduledoc """
  The editorial timeline rail — the spine of the Upcoming page.

  Renders the feed's relative-time buckets in order (Today → Beyond), each
  under a quiet marker label, with events as `EventCard`s. Proximity drives
  prominence: events the view-model flagged `hero?` render as large hero cards,
  the rest as compact rows. Empty buckets are skipped; an all-empty feed shows a
  single calm empty state.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents
  import MediaCentaurWeb.Components.Upcoming.EventCard, only: [event_card: 1]

  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaurWeb.Components.Upcoming.Present

  attr :feed, UpcomingFeed, required: true, doc: "The built `UpcomingFeed` view-model."
  attr :today, Date, required: true

  def rail(assigns) do
    assigns = assign(assigns, :groups, non_empty_groups(assigns.feed))

    ~H"""
    <div data-nav-zone="rail" class="space-y-8">
      <section :for={{bucket, events} <- @groups} class="space-y-2">
        <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {Present.bucket_label(bucket)}
        </h2>
        <div class="space-y-2">
          <.event_card
            :for={event <- events}
            event={event}
            today={@today}
            variant={if event.hero?, do: :hero, else: :compact}
          />
        </div>
      </section>

      <div
        :if={@groups == []}
        class="flex flex-col items-center justify-center gap-2 rounded-xl glass-surface px-6 py-16 text-center"
      >
        <.icon name="hero-calendar-days" class="size-8 text-base-content/20" />
        <p class="text-sm text-base-content/50">Nothing on the horizon yet.</p>
        <p class="text-xs text-base-content/30">Track a show or movie to see its releases here.</p>
      </div>
    </div>
    """
  end

  defp non_empty_groups(%UpcomingFeed{buckets: buckets}) do
    UpcomingFeed.bucket_order()
    |> Enum.map(fn bucket -> {bucket, Map.get(buckets, bucket, [])} end)
    |> Enum.reject(fn {_bucket, events} -> events == [] end)
  end
end
