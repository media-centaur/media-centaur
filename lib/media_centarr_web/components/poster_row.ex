defmodule MediaCentarrWeb.Components.PosterRow do
  @moduledoc """
  Horizontal poster row (8-up). Used on Home for "Recently Added" and
  "Watched Recently" rows.

  Each item is a map: `%{id, name, year, poster_url}`. `year` may be a
  string like "2023" or "S2 · 2026".
  """
  use Phoenix.Component

  attr :items, :list, required: true

  def poster_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="poster-row"
      class="grid grid-cols-4 sm:grid-cols-6 lg:grid-cols-8 gap-3"
    >
      <div :for={item <- @items} class="relative aspect-[2/3] rounded-lg overflow-hidden glass-inset">
        <img
          :if={item.poster_url}
          src={item.poster_url}
          class="absolute inset-0 w-full h-full object-cover"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/80 to-transparent"></div>
        <div class="absolute bottom-2 left-2 right-2">
          <div class="text-xs font-semibold text-white drop-shadow truncate">{item.name}</div>
          <div :if={item.year} class="text-[10px] text-white/70">{item.year}</div>
        </div>
      </div>
    </div>
    """
  end
end
