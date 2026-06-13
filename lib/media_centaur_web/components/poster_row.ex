defmodule MediaCentaurWeb.Components.PosterRow do
  @moduledoc """
  Horizontal poster row (8-up). Used on Home for the "Recently Added" row.

  Each item is an `Item` struct (see below). `year` may be a string like
  "2023" or "S2 · 2026".

  When `see_all_href` is set, a "See all" card renders as the last slot in
  the scrollable row, mirroring the Continue Watching row.
  """

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

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

  attr :see_all_href, :string,
    default: nil,
    doc: "when set, renders a trailing \"See all\" card navigating to this path"

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
        id={"poster-row-#{item.entity_id}"}
        type="button"
        phx-click="select_entity"
        phx-value-id={item.entity_id}
        class="card-hover relative aspect-[2/3] rounded overflow-hidden glass-inset block w-full text-left"
        data-row-item
        data-nav-item
        data-entity-id={item.entity_id}
        tabindex="0"
      >
        <img
          :if={item.poster_url}
          src={sized_image_url(item.poster_url, 480)}
          alt={item.name}
          class="absolute inset-0 w-full h-full object-cover"
          loading="eager"
          decoding="sync"
        />
        <%!-- Fallback only when artwork is missing — the poster image itself
              already carries the title, so showing it again is redundant. --%>
        <div :if={!item.poster_url} class="absolute inset-x-2 bottom-2">
          <div class="text-xs font-semibold text-white text-on-image truncate">{item.name}</div>
          <div :if={item.year} class="text-[10px] text-white/70 text-on-image">{item.year}</div>
        </div>
      </button>

      <.link
        :if={@see_all_href}
        navigate={@see_all_href}
        class="card-hover relative aspect-[2/3] rounded overflow-hidden glass-inset flex flex-col items-center justify-center gap-2 text-base-content/60 hover:text-primary hover:bg-base-content/5"
        data-component="poster-row-see-all"
        data-row-item
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-arrow-right-circle" class="size-10" />
        <span class="text-sm font-medium">See all</span>
      </.link>
    </div>
    """
  end
end
