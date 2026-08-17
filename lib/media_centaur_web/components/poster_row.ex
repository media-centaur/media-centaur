defmodule MediaCentaurWeb.Components.PosterRow do
  @moduledoc """
  Horizontal poster row. Used on Home for the "Recently Added" row.

  Cards are the shared 2:3 poster (`--card-poster-w`), so they are the same
  size as the library grid's — the row's "See all" lands on `/library`, and
  posters that resized across that step would read as two different objects.
  How many fit is left to `.row-scroll-poster`; the last one is deliberately
  cut off, which is what says the row scrolls.

  Each item is an `Item` struct (see below). `year` may be a string like
  "2023" or "S2 · 2026".

  When `see_all_href` is set, a "See all" card renders as the last slot in
  the scrollable row, mirroring the Continue Watching row.
  """

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [poster_src: 1]

  alias MediaCentaurWeb.Components.PlayOverlay

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

  attr :show_play_button, :boolean,
    default: true,
    doc:
      "When false, suppresses the hover play overlay (UIDR-027). Driven by the `card_play_button` Settings entry (see `MediaCentaur.CardPlayButton`)."

  def poster_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="poster-row"
      data-scroll-row="poster-row"
      class="row-scroll row-scroll-poster"
    >
      <%!-- A div, not a <button>: the play overlay nests a real button
            inside (UIDR-027) and buttons cannot nest. Same pattern as the
            library poster card. --%>
      <div
        :for={item <- @items}
        id={"poster-row-#{item.entity_id}"}
        phx-click="select_entity"
        phx-value-id={item.entity_id}
        class="card-hover play-overlay-host relative aspect-[2/3] rounded overflow-hidden glass-inset block w-full text-left"
        data-row-item
        data-nav-item
        data-entity-id={item.entity_id}
        tabindex="0"
      >
        <img
          :if={item.poster_url}
          src={poster_src(item.poster_url)}
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

        <PlayOverlay.play_overlay :if={@show_play_button} entity_id={item.entity_id} />
      </div>

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
