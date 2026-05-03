defmodule MediaCentarrWeb.Components.ComingUpMarquee do
  @moduledoc """
  Cinematic marquee for tracked upcoming releases. One hero card (the
  soonest release) plus up to three secondary tiles. Used on Home.

  The shape is intentionally hero-first rather than a horizontal row of
  identical cards. When a single show has many upcoming episodes, those
  collapse into a "+ N more" rollup line on the hero rather than
  repeating the same artwork. When the library is sparse, the layout
  collapses to a single full-width hero so a lonely card still feels
  deliberate.

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
      class={[
        "grid gap-4",
        if(@marquee.secondaries == [],
          do: "grid-cols-1 h-[320px]",
          else: "grid-cols-[1.7fr_1fr] h-[360px]"
        )
      ]}
    >
      <.hero_card item={@marquee.hero} />
      <div :if={@marquee.secondaries != []} class="flex flex-col gap-2.5 min-h-0">
        <.secondary_tile
          :for={item <- @marquee.secondaries}
          item={item}
          fill?={length(@marquee.secondaries) > 1}
        />
      </div>
    </div>
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
        src={@item.backdrop_url}
        alt=""
        class="absolute inset-0 w-full h-full object-cover object-top"
        loading="lazy"
      />
      <div class="absolute inset-0 bg-gradient-to-r from-black/90 via-black/45 to-transparent"></div>
      <div class="relative z-10 p-8 max-w-[60%]">
        <div class="text-[11px] tracking-[0.22em] uppercase font-bold text-primary mb-2">
          {@item.eyebrow}
        </div>
        <img
          :if={@item.logo_url}
          src={@item.logo_url}
          alt={@item.name}
          class="max-h-24 max-w-full object-contain object-left mb-3 drop-shadow-[0_2px_12px_rgba(0,0,0,0.6)]"
        />
        <div
          :if={!@item.logo_url}
          class="text-5xl font-extrabold tracking-tight text-white mb-3 drop-shadow-[0_2px_12px_rgba(0,0,0,0.6)]"
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
        src={@item.backdrop_url}
        alt=""
        class="absolute inset-0 w-full h-full object-cover object-top"
        loading="lazy"
      />
      <%!-- Diagonal scrim — strongest at bottom-left where content sits, --%>
      <%!-- letting the artwork breathe on the top-right. Survives bright artwork. --%>
      <div class="absolute inset-0 bg-gradient-to-tr from-black/85 via-black/30 to-transparent"></div>
      <div class="relative z-10 px-4 pb-3 pt-4 max-w-[80%]">
        <div class="text-[10px] tracking-[0.22em] uppercase font-bold text-primary mb-1.5 truncate">
          {@item.eyebrow}
        </div>
        <img
          :if={@item.logo_url}
          src={@item.logo_url}
          alt={@item.name}
          class="max-h-9 max-w-full object-contain object-left drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
        />
        <div
          :if={!@item.logo_url}
          class="text-lg font-bold text-white truncate drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
        >
          {@item.name}
        </div>
        <div :if={@item.sub} class="text-xs text-white/70 truncate mt-1.5 tracking-wide">
          {@item.sub}
        </div>
        <span
          :if={@item.badge}
          class={[
            "inline-block mt-2 text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded",
            badge_class(@item.badge.variant)
          ]}
        >
          {@item.badge.label}
        </span>
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
      type="button"
      phx-click="select_entity"
      phx-value-id={@item.entity_id}
      data-card={@data_card}
      data-row-item
      class={[@class, "w-full"]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp tile_link(assigns) do
    ~H"""
    <.link navigate="/upcoming" data-card={@data_card} data-row-item class={@class}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp badge_class(:success), do: "bg-success/25 text-success"
  defp badge_class(:info), do: "bg-info/25 text-info"
  defp badge_class(_), do: "bg-base-content/15 text-base-content/75"
end
