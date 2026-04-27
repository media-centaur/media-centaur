defmodule MediaCentarrWeb.Components.ContinueWatchingRow do
  @moduledoc """
  Horizontal row of backdrop cards for in-progress titles. Used on Home.
  Each item is a map: `%{id, name, subtitle, progress_pct, backdrop_url}`.
  """
  use Phoenix.Component

  attr :items, :list, required: true

  def continue_watching_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="continue-watching"
      class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4"
    >
      <div :for={item <- @items} class="relative aspect-[16/9] rounded-lg overflow-hidden glass-inset">
        <img
          :if={item.backdrop_url}
          src={item.backdrop_url}
          class="absolute inset-0 w-full h-full object-cover object-top"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent">
        </div>
        <div class="absolute bottom-2 left-2 right-2">
          <div class="text-[10px] uppercase tracking-wider text-white/70 truncate">
            {item.subtitle}
          </div>
          <div class="text-sm font-semibold text-white drop-shadow truncate">{item.name}</div>
        </div>
        <div class="absolute left-0 right-0 bottom-0 h-1 bg-black/50">
          <div class="h-full bg-primary" style={"width: #{item.progress_pct}%"}></div>
        </div>
      </div>
    </div>
    """
  end
end
