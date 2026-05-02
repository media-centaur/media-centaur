defmodule MediaCentarrWeb.Components.PosterRow do
  @moduledoc """
  Horizontal poster row (8-up). Used on Home for the "Recently Added" row.

  Each item is an `Item` struct (see below). `year` may be a string like
  "2023" or "S2 · 2026".
  """

  use Phoenix.Component

  defmodule Item do
    @moduledoc "View-model for a single PosterRow card."
    @enforce_keys [:id, :entity_id, :name, :year, :poster_url]
    defstruct [:id, :entity_id, :name, :year, :poster_url]

    @type t :: %__MODULE__{
            id: term(),
            entity_id: String.t(),
            name: String.t(),
            year: String.t() | nil,
            poster_url: String.t() | nil
          }
  end

  attr :items, :list, required: true, doc: "list of `Item.t()`"

  def poster_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="poster-row"
      data-scroll-row="poster-row"
      class="row-scroll row-scroll-poster"
    >
      <button
        :for={item <- @items}
        type="button"
        phx-click="select_entity"
        phx-value-id={item.entity_id}
        class="card-hover relative aspect-[2/3] rounded overflow-hidden glass-inset block w-full text-left"
        data-row-item
      >
        <img
          :if={item.poster_url}
          src={item.poster_url}
          alt={item.name}
          class="absolute inset-0 w-full h-full object-cover"
          loading="lazy"
        />
        <%!-- Fallback only when artwork is missing — the poster image itself
              already carries the title, so showing it again is redundant. --%>
        <div :if={!item.poster_url} class="absolute inset-x-2 bottom-2">
          <div class="text-xs font-semibold text-white drop-shadow truncate">{item.name}</div>
          <div :if={item.year} class="text-[10px] text-white/70">{item.year}</div>
        </div>
      </button>
    </div>
    """
  end
end
