defmodule MediaCentaurWeb.Components.Upcoming.Stragglers do
  @moduledoc """
  The "Tracking — nothing scheduled yet" catch-all: tracked titles with no dated
  release (hiatus shows, movies with no announced date). Quiet and greyscale —
  it keeps these discoverable without competing with the forecast. Each row
  opens the title's detail panel. Renders nothing when empty.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents

  attr :stragglers, :list,
    default: [],
    doc: "List of `UpcomingFeed.Straggler` — tracked items with no dated release."

  def stragglers(assigns) do
    ~H"""
    <div :if={@stragglers != []} data-nav-zone="stragglers" class="space-y-2">
      <h2 class="text-xs font-medium uppercase tracking-wider text-base-content/40">
        Tracking — nothing scheduled yet
      </h2>
      <div class="space-y-0.5">
        <button
          :for={straggler <- @stragglers}
          type="button"
          class="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left transition-colors hover:bg-base-content/[0.03]"
          data-nav-item
          tabindex="0"
          phx-click="select_event"
          phx-value-item-id={straggler.item_id}
        >
          <.icon name={media_icon(straggler.media_type)} class="size-4 shrink-0 text-base-content/30" />
          <span class="truncate text-sm text-base-content/60">{straggler.name}</span>
        </button>
      </div>
    </div>
    """
  end

  defp media_icon(:tv_series), do: "hero-tv"
  defp media_icon(:movie), do: "hero-film"
end
