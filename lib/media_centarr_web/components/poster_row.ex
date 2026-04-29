defmodule MediaCentarrWeb.Components.PosterRow do
  @moduledoc """
  Horizontal poster row (8-up). Used on Home for the "Recently Added" row.

  Each item is a map: `%{id, name, year, poster_url}`.
  `year` may be a string like "2023" or "S2 · 2026".
  """
  use Phoenix.Component

  attr :items, :list, required: true

  def poster_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="poster-row"
      data-scroll-row="poster-row"
      class="row-scroll row-scroll-poster"
    >
      <div
        :for={item <- @items}
        class="card-hover relative aspect-[2/3] rounded overflow-hidden glass-inset"
        data-row-item
      >
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
