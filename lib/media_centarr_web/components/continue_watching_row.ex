defmodule MediaCentarrWeb.Components.ContinueWatchingRow do
  @moduledoc """
  Horizontal row of backdrop cards for in-progress titles. Used on Home.
  Each item is a map: `%{id, name, subtitle, progress_pct, backdrop_url}`.

  Renders up to 4 actual cards plus a "See all" placeholder card as the
  5th slot. The placeholder navigates to `/library?in_progress=1` so
  users can browse the full set of in-progress titles.
  """
  use Phoenix.Component
  import MediaCentarrWeb.CoreComponents, only: [icon: 1]

  attr :items, :list, required: true

  def continue_watching_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="continue-watching"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4"
    >
      <div
        :for={item <- Enum.take(@items, 4)}
        class="relative aspect-[16/9] rounded-lg overflow-hidden glass-inset"
      >
        <img
          :if={item.backdrop_url}
          src={item.backdrop_url}
          class="absolute inset-0 w-full h-full object-cover object-top"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent">
        </div>
        <div class="absolute bottom-2 left-2 right-2">
          <div class="text-[11px] uppercase tracking-wider text-white/70 truncate">
            {item.subtitle}
          </div>
          <div class="text-base font-semibold text-white drop-shadow truncate">{item.name}</div>
        </div>
        <div class="absolute left-0 right-0 bottom-0 h-1 bg-black/50">
          <div class="h-full bg-primary" style={"width: #{item.progress_pct}%"}></div>
        </div>
      </div>

      <.link
        navigate="/library?in_progress=1"
        class="relative aspect-[16/9] rounded-lg overflow-hidden glass-inset flex flex-col items-center justify-center gap-2 text-base-content/60 hover:text-primary hover:bg-base-content/5 transition-colors"
        data-component="continue-watching-see-all"
      >
        <.icon name="hero-arrow-right-circle" class="size-8" />
        <span class="text-sm font-medium">See all in-progress</span>
      </.link>
    </div>
    """
  end
end
