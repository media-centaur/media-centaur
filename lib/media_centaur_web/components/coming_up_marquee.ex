defmodule MediaCentaurWeb.Components.ComingUpMarquee do
  @moduledoc """
  Cinematic marquee for tracked upcoming releases. One hero card (the
  soonest release) plus up to three secondary tiles. Used on Home.

  The shape is intentionally hero-first rather than a horizontal row of
  identical cards. When a single show has many upcoming episodes, those
  collapse into a "+ N more" rollup line on the hero rather than
  repeating the same artwork. When there are no secondaries, the hero
  keeps its sized column (`1.7fr`) and the secondary track is filled with
  a "See all" placeholder linking to `/upcoming` — mirroring the Continue
  Watching row — rather than stretching the hero full-width.

  Tiles open the entity detail modal in place via `phx-click="select_entity"`
  when the release item has a paired library entity. Items without an
  `entity_id` fall back to navigating to `/upcoming` so a click is never
  inert.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Depends on release-tracking timer state — covered by page smoke tests"

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  # Painted widths for the two tile shapes, at 4K device pixels: the grid is
  # `1.7fr 1fr` inside a 1920 CSS px composition that scales 2× on a UHD
  # panel. Backdrops fill their tile; logos are height-capped
  # (`max-h-24` / `max-h-9`) so their width follows the logo's aspect.

  defmodule Item do
    @moduledoc """
    One card in the marquee. Used for both the hero and the secondary tiles.

    * `eyebrow` — the small uppercase line above the title (e.g.
      "Tonight · S05E04", "Tomorrow · 9 PM", "Sat · May 11 · S02E08").
    * `rollup` — hero-only contextual line ("+ 6 more this season",
      "season finale", "season premiere"). `nil` when the show has no
      additional upcoming releases.
    * `sub` — secondary-tile-only sub-line ("S02E08", "+ 7 more this
      season"). `nil` for the hero.
    """
    @enforce_keys [
      :id,
      :entity_id,
      :name,
      :eyebrow,
      :badge,
      :backdrop_url,
      :logo_url,
      :rollup,
      :sub
    ]
    defstruct [:id, :entity_id, :name, :eyebrow, :badge, :backdrop_url, :logo_url, :rollup, :sub]

    @type badge :: %{label: String.t(), variant: :success | :info | :default}

    @type t :: %__MODULE__{
            id: term(),
            entity_id: String.t() | nil,
            name: String.t(),
            eyebrow: String.t(),
            badge: badge() | nil,
            backdrop_url: String.t() | nil,
            logo_url: String.t() | nil,
            rollup: String.t() | nil,
            sub: String.t() | nil
          }
  end

  defmodule Marquee do
    @moduledoc "View-model for the whole marquee — hero plus 0..3 secondaries."
    @enforce_keys [:hero, :secondaries]
    defstruct [:hero, :secondaries]

    @type t :: %__MODULE__{
            hero: Item.t() | nil,
            secondaries: [Item.t()]
          }
  end

  attr :marquee, Marquee, required: true

  def coming_up_marquee(assigns) do
    ~H"""
    <div
      :if={@marquee.hero != nil}
      data-component="coming-up-marquee"
      class="grid gap-4 grid-cols-[1.7fr_1fr] h-[360px]"
    >
      <.hero_card item={@marquee.hero} />
      <div :if={@marquee.secondaries != []} class="flex flex-col gap-2.5 min-h-0">
        <.secondary_tile
          :for={item <- @marquee.secondaries}
          item={item}
          fill?={length(@marquee.secondaries) > 1}
        />
      </div>
      <.see_all_tile :if={@marquee.secondaries == []} />
    </div>
    """
  end

  # Fills the otherwise-empty secondary column when the hero is the only
  # upcoming release, mirroring the Continue Watching row's trailing
  # "See all" slot rather than leaving dead space.
  defp see_all_tile(assigns) do
    ~H"""
    <.link
      navigate="/incoming"
      class="card-hover relative rounded-xl overflow-hidden glass-inset flex flex-col items-center justify-center gap-2 text-base-content/60 hover:text-primary hover:bg-base-content/5"
      data-component="coming-up-see-all"
      data-row-item
      data-nav-item
      tabindex="0"
    >
      <.icon name="hero-arrow-right-circle" class="size-10" />
      <span class="text-sm font-medium">See all</span>
    </.link>
    """
  end

  attr :item, Item, required: true

  defp hero_card(assigns) do
    ~H"""
    <.tile_link
      item={@item}
      data_card="hero"
      class="card-hover relative rounded-xl overflow-hidden glass-inset flex items-end text-left"
    >
      <img
        :if={@item.backdrop_url}
        src={sized_image_url(@item.backdrop_url, 1920)}
        alt=""
        class="absolute inset-0 w-full h-full object-cover object-top"
        loading="eager"
        decoding="sync"
      />
      <div class="absolute inset-0 bg-gradient-to-r from-black/90 via-black/45 to-transparent"></div>
      <div class="relative z-10 p-8 max-w-[60%]">
        <div class="text-[11px] tracking-[0.22em] uppercase font-bold text-primary mb-2">
          {@item.eyebrow}
        </div>
        <img
          :if={@item.logo_url}
          src={sized_image_url(@item.logo_url, 960)}
          alt={@item.name}
          class="max-h-24 max-w-full object-contain object-left mb-3 text-on-image-lg"
        />
        <div
          :if={!@item.logo_url}
          class="text-5xl font-extrabold tracking-tight text-white mb-3 text-on-image-lg"
        >
          {@item.name}
        </div>
        <span
          :if={@item.badge}
          class={[
            "inline-block text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded",
            badge_class(@item.badge.variant)
          ]}
        >
          {@item.badge.label}
        </span>
        <div :if={@item.rollup} class={[@item.badge && "mt-3", "text-sm text-white/70 tracking-wide"]}>
          {@item.rollup}
        </div>
      </div>
    </.tile_link>
    """
  end

  attr :item, Item, required: true
  attr :fill?, :boolean, default: true

  defp secondary_tile(assigns) do
    ~H"""
    <.tile_link
      item={@item}
      data_card="secondary"
      class={[
        "card-hover relative rounded-lg overflow-hidden glass-inset flex items-end text-left",
        @fill? && "flex-1 min-h-0",
        !@fill? && "aspect-video my-auto"
      ]}
    >
      <img
        :if={@item.backdrop_url}
        src={sized_image_url(@item.backdrop_url, 1280)}
        alt=""
        class="absolute inset-0 w-full h-full object-cover object-top"
        loading="eager"
        decoding="sync"
      />
      <%!-- Diagonal scrim — strongest at bottom-left where content sits, --%>
      <%!-- letting the artwork breathe on the top-right. Survives bright artwork. --%>
      <div class="absolute inset-0 bg-gradient-to-tr from-black/85 via-black/30 to-transparent"></div>
      <%!-- Status badge floats top-right so the content stack stays the --%>
      <%!-- same height whether or not the release has a status. --%>
      <span
        :if={@item.badge}
        class={[
          "absolute top-2 right-2 z-20 text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded backdrop-blur-md",
          badge_class(@item.badge.variant)
        ]}
      >
        {@item.badge.label}
      </span>
      <div class="relative z-10 px-4 pb-3 pt-4 max-w-[80%]">
        <div class="text-[10px] tracking-[0.22em] uppercase font-bold text-primary mb-1.5 truncate">
          {@item.eyebrow}
        </div>
        <img
          :if={@item.logo_url}
          src={sized_image_url(@item.logo_url, 480)}
          alt={@item.name}
          class="max-h-9 max-w-full object-contain object-left text-on-image-lg"
        />
        <div
          :if={!@item.logo_url}
          class="text-lg font-bold text-white truncate text-on-image-lg"
        >
          {@item.name}
        </div>
        <div :if={@item.sub} class="text-xs text-white/70 truncate mt-1.5 tracking-wide">
          {@item.sub}
        </div>
      </div>
    </.tile_link>
    """
  end

  # Renders either a phx-click button (when entity_id is known so the modal
  # can open in place) or a navigate link to /upcoming as the fallback.
  attr :item, Item, required: true
  attr :data_card, :string, required: true

  attr :class, :any,
    required: true,
    doc: "Tailwind class string or list — passed through to the rendered link/button."

  slot :inner_block, required: true

  defp tile_link(%{item: %Item{entity_id: entity_id}} = assigns) when is_binary(entity_id) do
    ~H"""
    <button
      id={"marquee-tile-#{@item.entity_id}"}
      type="button"
      phx-click="select_entity"
      phx-value-id={@item.entity_id}
      data-card={@data_card}
      data-row-item
      data-nav-item
      data-entity-id={@item.entity_id}
      tabindex="0"
      class={[@class, "w-full"]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp tile_link(assigns) do
    ~H"""
    <.link
      navigate="/incoming"
      data-card={@data_card}
      data-row-item
      data-nav-item
      tabindex="0"
      class={@class}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp badge_class(:success), do: "bg-success/25 text-success"
  defp badge_class(:info), do: "bg-info/25 text-info"
  defp badge_class(_), do: "bg-base-content/15 text-base-content/75"
end
