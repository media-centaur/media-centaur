defmodule MediaCentaurWeb.Components.ContinueWatchingRow do
  @moduledoc """
  Horizontal-scrolling row of backdrop cards for in-progress titles. Used
  on Home. Each item is a `Item` struct (see below).

  All loaded items render — the row scrolls horizontally so callers can
  pass as many as they like. A "See all" placeholder appears as the last
  slot. Cards carry `data-nav-item` so the host can wrap the row in a
  `data-nav-zone` (a SHELF context) for keyboard/gamepad navigation — see
  HomeLive and the `input-system` skill.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Depends on watch-history feed — covered by page smoke tests"

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaurWeb.Components.PlayOverlay

  # Cards sit in a `.row-scroll-backdrop-lg` track, so each is
  # `--card-backdrop-w` (453 CSS px, app.css) — 906 device px on a 4K panel,
  # which `960` covers. The logo is height-capped (`max-h-20`) and bounded to
  # 80% of the card.

  defmodule Item do
    @moduledoc "View-model for a single Continue Watching card."
    @enforce_keys [:id, :entity_id, :name, :progress_pct, :backdrop_url]
    defstruct [
      :id,
      :entity_id,
      :name,
      :progress_pct,
      :backdrop_url,
      logo_url: nil
    ]

    @type t :: %__MODULE__{
            id: term(),
            entity_id: String.t(),
            name: String.t(),
            progress_pct: 0..100,
            backdrop_url: String.t() | nil,
            logo_url: String.t() | nil
          }
  end

  attr :items, :list, required: true, doc: "list of `Item.t()`"

  attr :show_play_button, :boolean,
    default: true,
    doc:
      "When false, suppresses the hover play overlay (UIDR-027). Driven by the `card_play_button` Settings entry (see `MediaCentaur.Preferences.CardPlayButton`)."

  def continue_watching_row(assigns) do
    ~H"""
    <div
      :if={@items != []}
      data-component="continue-watching"
      data-scroll-row="continue-watching"
      class="row-scroll row-scroll-backdrop-lg"
    >
      <%!-- A div, not a <button>: the play overlay nests a real button
            inside (UIDR-027) and buttons cannot nest. --%>
      <div
        :for={item <- @items}
        id={"continue-watching-#{item.entity_id}"}
        phx-click="select_entity"
        phx-value-id={item.entity_id}
        class="card-hover play-overlay-host relative aspect-[16/9] rounded-lg overflow-hidden glass-inset block w-full text-left"
        data-row-item
        data-nav-item
        data-entity-id={item.entity_id}
        tabindex="0"
      >
        <img
          :if={item.backdrop_url}
          src={sized_image_url(item.backdrop_url, 960)}
          class="absolute inset-0 w-full h-full object-cover object-top"
          loading="eager"
          decoding="sync"
        />
        <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent">
        </div>
        <div class="absolute bottom-4 left-4 right-4">
          <img
            :if={item.logo_url}
            src={sized_image_url(item.logo_url, 320)}
            alt={item.name}
            class="max-h-20 max-w-[80%] object-contain object-left text-on-image-lg"
          />
          <div
            :if={!item.logo_url}
            class="text-2xl font-semibold text-white text-on-image-lg truncate"
          >
            {item.name}
          </div>
        </div>
        <PlayOverlay.play_overlay :if={@show_play_button} entity_id={item.entity_id} size={:lg} />

        <div class="absolute left-0 right-0 bottom-0 h-1.5 bg-black/50">
          <div class="h-full bg-primary" style={"width: #{item.progress_pct}%"}></div>
        </div>
      </div>

      <.link
        navigate="/library?sort=watched"
        class="card-hover relative aspect-[16/9] rounded-lg overflow-hidden glass-inset flex flex-col items-center justify-center gap-2 text-base-content/60 hover:text-primary hover:bg-base-content/5"
        data-component="continue-watching-see-all"
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
