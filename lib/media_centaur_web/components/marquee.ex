defmodule MediaCentaurWeb.Components.Marquee do
  @moduledoc """
  The marquee: a shelf whose first title is featured. One lead tile, then
  columns of up to three stacked tiles, scrolling right inside
  `ScrollRow.scroll_row/1`, ending in a See all tile when the shelf has a
  page of its own (`SeeAllTile`). The See all tile takes the slot after the
  last tile, so it shares a column when one has room and starts a column of
  its own after a full one (`columns/2`). Sharing a column, it is one slot
  high — a third of the column — and the tiles above it share the rest; alone
  in a column it fills it.

  Widths come from the row's width, not from fixed card sizes:
  `column = (row − 2 × gap) ÷ (ratio + 1 + peek)` and `lead = ratio ×
  column` (`.row-scroll-marquee` in `app.css`, container query units on
  `.marquee`), so the lead tile and the first column fill the row the way a
  two-column grid would, with a quarter of the next column showing as the
  sign that the shelf scrolls. The last column grows into free width, so a
  marquee that fits ends flush.

  The marquee draws what it is given and caps nothing; the caller decides
  how many items to pass. Home's Coming Up is the first user
  (`HomeLive.Logic.coming_up_items/2`, up to 7 shows: the lead tile and
  two full columns, See all alone in a third).

  A tile opens the title detail in place (UIDR-043): `select_entity` when
  the item has a library entity, else `open_title` by its TMDB ref — the
  host (`Live.TitleDetailHost`) answers both. Keyboard and gamepad move by
  screen position (the SHELF context's geometry), so up and down move
  within a column and right reaches the next one.
  """

  use Phoenix.Component
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_srcset: 2, sized_image_url: 2]

  alias MediaCentaurWeb.Components.ScrollRow
  alias MediaCentaurWeb.Components.SeeAllTile
  alias MediaCentaurWeb.TitleRef

  # Painted widths at 4K device pixels: the lead tile is ~1018 design px
  # and a column ~599 at a full-width row, doubled on a UHD panel. Logos
  # are height-capped (`max-h-24` / `max-h-9`), so their width follows the
  # logo's aspect.

  defmodule Item do
    @moduledoc """
    One tile of a marquee — the lead tile and the smaller tiles share it.

    * `eyebrow` — the small uppercase line above the name ("Tonight ·
      S05E04", "Tomorrow", "Sat").
    * `line` — the line under the name ("+ 6 more this season", "S02E08"),
      or `nil`.
    * `badge` — a state chip (`%{label:, variant: :success | :info |
      :default}`), or `nil`.
    * `entity_id` / `ref` — what a press opens: the library entity when
      there is one, else the TMDB ref `{tmdb_id, media_type}`.
    """
    alias MediaCentaurWeb.TitleRef

    @enforce_keys [:entity_id, :ref, :name, :eyebrow, :badge, :backdrop_url, :logo_url, :line]
    defstruct @enforce_keys

    @type badge :: %{label: String.t(), variant: :success | :info | :default}

    @type t :: %__MODULE__{
            entity_id: String.t() | nil,
            ref: {integer(), atom()},
            name: String.t(),
            eyebrow: String.t(),
            badge: badge() | nil,
            backdrop_url: String.t() | nil,
            logo_url: String.t() | nil,
            line: String.t() | nil
          }

    @doc "The tile's identity on the page: its library entity, else its TMDB ref."
    @spec key(t()) :: String.t()
    def key(%__MODULE__{entity_id: entity_id}) when is_binary(entity_id), do: entity_id
    def key(%__MODULE__{ref: ref}), do: TitleRef.param(ref)
  end

  @column_size 3

  @doc """
  The tiles after the lead, in columns of up to three, with `:see_all` in
  the slot after the last tile when `see_all?`.
  """
  @spec columns([Item.t()], boolean()) :: [[Item.t() | :see_all]]
  def columns(tiles, see_all?) do
    slots = if see_all?, do: tiles ++ [:see_all], else: tiles
    Enum.chunk_every(slots, @column_size)
  end

  attr :id, :string, required: true, doc: "the row's DOM id; tile and column ids derive from it"
  attr :items, :list, required: true, doc: "`Item.t()`s, the lead tile first; `[]` renders nothing"

  attr :see_all_href, :string,
    default: nil,
    doc: "the shelf's page; when set, the See all tile ends the marquee"

  def marquee(assigns) do
    assigns =
      case assigns.items do
        [] ->
          assign(assigns, lead: nil, columns: [])

        [lead | tiles] ->
          assign(assigns,
            lead: lead,
            columns: tiles |> columns(assigns.see_all_href != nil) |> Enum.with_index()
          )
      end

    ~H"""
    <div :if={@lead} class="marquee" data-component="marquee">
      <ScrollRow.scroll_row id={@id} variant={:marquee}>
        <.tile_button row_id={@id} item={@lead} card="lead" class="marquee-lead rounded-xl">
          <.lead_body item={@lead} />
        </.tile_button>
        <div
          :for={{column, index} <- @columns}
          id={"#{@id}-column-#{index}"}
          class="marquee-column"
        >
          <.slot_tile :for={slot <- column} row_id={@id} slot={slot} see_all_href={@see_all_href} />
        </div>
      </ScrollRow.scroll_row>
    </div>
    """
  end

  attr :row_id, :string, required: true
  attr :slot, :any, required: true, doc: "an `Item.t()`, or `:see_all`"
  attr :see_all_href, :string, default: nil

  defp slot_tile(%{slot: :see_all} = assigns) do
    ~H"""
    <SeeAllTile.see_all_tile navigate={@see_all_href} shape={:fill} data-component="marquee-see-all" />
    """
  end

  defp slot_tile(assigns) do
    ~H"""
    <.tile_button row_id={@row_id} item={@slot} card="tile" class="rounded-lg">
      <.tile_body item={@slot} />
    </.tile_button>
    """
  end

  # The tile opens the title detail in place: by its library entity when
  # it has one, else by its TMDB ref.
  attr :row_id, :string, required: true
  attr :item, Item, required: true
  attr :card, :string, required: true, values: ["lead", "tile"]
  attr :class, :string, required: true
  slot :inner_block, required: true

  defp tile_button(assigns) do
    ~H"""
    <button
      id={"#{@row_id}-#{Item.key(@item)}"}
      type="button"
      phx-click={if @item.entity_id, do: "select_entity", else: "open_title"}
      phx-value-id={@item.entity_id}
      phx-value-ref={if is_nil(@item.entity_id), do: TitleRef.param(@item.ref)}
      data-card={@card}
      data-row-item
      data-nav-item
      data-entity-id={Item.key(@item)}
      tabindex="0"
      class={[
        "card-hover relative overflow-hidden glass-inset flex items-end text-left cursor-pointer",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :item, Item, required: true

  defp lead_body(assigns) do
    ~H"""
    <img
      :if={@item.backdrop_url}
      src={sized_image_url(@item.backdrop_url, 1920)}
      srcset={sized_image_srcset(@item.backdrop_url, [1920, 2560])}
      sizes="55vw"
      alt=""
      class="absolute inset-0 w-full h-full object-cover object-top"
      loading="eager"
      decoding="sync"
    />
    <div class="absolute inset-0 bg-gradient-to-r from-black/90 via-black/45 to-transparent"></div>
    <div class="relative z-10 p-8 max-w-[60%] max-compact:p-3 max-compact:max-w-full">
      <div class="text-[11px] tracking-[0.22em] uppercase font-bold text-primary mb-2">
        {@item.eyebrow}
      </div>
      <img
        :if={@item.logo_url}
        src={sized_image_url(@item.logo_url, 960)}
        alt={@item.name}
        class="max-h-24 max-w-full object-contain object-left mb-3 text-on-image-lg max-compact:max-h-12"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@item.logo_url}
        class="text-5xl font-extrabold tracking-tight text-white mb-3 text-on-image-lg max-compact:text-xl"
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
      <div
        :if={@item.line}
        class={[@item.badge && "mt-3", "text-sm text-white/70 tracking-wide max-compact:hidden"]}
      >
        {@item.line}
      </div>
    </div>
    """
  end

  attr :item, Item, required: true

  defp tile_body(assigns) do
    ~H"""
    <img
      :if={@item.backdrop_url}
      src={sized_image_url(@item.backdrop_url, 1280)}
      srcset={sized_image_srcset(@item.backdrop_url, [1280, 1920])}
      sizes="33vw"
      alt=""
      class="absolute inset-0 w-full h-full object-cover object-top"
      loading="eager"
      decoding="sync"
    />
    <%!-- Diagonal scrim — strongest at bottom-left where content sits, --%>
    <%!-- letting the artwork breathe on the top-right. Survives bright artwork. --%>
    <div class="absolute inset-0 bg-gradient-to-tr from-black/85 via-black/30 to-transparent"></div>
    <%!-- The badge floats top-right so the content stack stays the same --%>
    <%!-- height whether or not the release has a status. --%>
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
        loading="eager"
        decoding="sync"
      />
      <div :if={!@item.logo_url} class="text-lg font-bold text-white truncate text-on-image-lg">
        {@item.name}
      </div>
      <div :if={@item.line} class="text-xs text-white/70 truncate mt-1.5 tracking-wide">
        {@item.line}
      </div>
    </div>
    """
  end

  defp badge_class(:success), do: "bg-success/25 text-success"
  defp badge_class(:info), do: "bg-info/25 text-info"
  defp badge_class(_), do: "bg-base-content/15 text-base-content/75"
end
