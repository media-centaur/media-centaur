defmodule MediaCentarrWeb.Components.ContinueWatchingRow do
  @moduledoc """
  Horizontal-scrolling row of backdrop cards for in-progress titles. Used
  on Home. Each item is a `Item` struct (see below).

  All loaded items render — the row scrolls horizontally so callers can
  pass as many as they like. A "See all" placeholder appears as the last
  slot. Per-row keyboard/gamepad navigation is planned (each row will
  become its own nav-zone) but not yet wired.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Depends on watch-history feed — covered by page smoke tests"

  use Phoenix.Component
  import MediaCentarrWeb.CoreComponents, only: [icon: 1]

  defmodule Item do
    @moduledoc "View-model for a single Continue Watching card."
    @enforce_keys [:id, :entity_id, :name, :progress_pct, :backdrop_url]
    defstruct [
      :id,
      :entity_id,
      :name,
      :progress_pct,
      :backdrop_url,
      logo_url: nil,
      autoplay: false
    ]

    @type t :: %__MODULE__{
            id: term(),
            entity_id: String.t(),
            name: String.t(),
            progress_pct: 0..100,
            backdrop_url: String.t() | nil,
            logo_url: String.t() | nil,
            autoplay: boolean()
          }
  end

  attr :items, :list, required: true, doc: "list of `Item.t()`"

  def continue_watching_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="continue-watching"
      data-scroll-row="continue-watching"
      class="row-scroll row-scroll-backdrop-lg"
    >
      <button
        :for={item <- @items}
        type="button"
        phx-click="select_entity"
        phx-value-id={item.entity_id}
        phx-value-autoplay={if item.autoplay, do: "1"}
        class="card-hover relative aspect-[16/9] rounded-lg overflow-hidden glass-inset block w-full text-left"
        data-row-item
      >
        <img
          :if={item.backdrop_url}
          src={item.backdrop_url}
          class="absolute inset-0 w-full h-full object-cover object-top"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent">
        </div>
        <div class="absolute bottom-4 left-4 right-4">
          <img
            :if={item.logo_url}
            src={item.logo_url}
            alt={item.name}
            class="max-h-20 max-w-[80%] object-contain object-left drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
          />
          <div
            :if={!item.logo_url}
            class="text-2xl font-semibold text-white drop-shadow truncate"
          >
            {item.name}
          </div>
        </div>
        <div class="absolute left-0 right-0 bottom-0 h-1.5 bg-black/50">
          <div class="h-full bg-primary" style={"width: #{item.progress_pct}%"}></div>
        </div>
      </button>

      <.link
        navigate="/library?in_progress=1"
        class="card-hover relative aspect-[16/9] rounded-lg overflow-hidden glass-inset flex flex-col items-center justify-center gap-2 text-base-content/60 hover:text-primary hover:bg-base-content/5"
        data-component="continue-watching-see-all"
        data-row-item
      >
        <.icon name="hero-arrow-right-circle" class="size-10" />
        <span class="text-sm font-medium">See all</span>
      </.link>
    </div>
    """
  end
end
