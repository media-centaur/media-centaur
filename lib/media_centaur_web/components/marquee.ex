defmodule MediaCentaurWeb.Components.Marquee do
  @moduledoc """
  The marquee: a shelf whose first title is featured. One lead tile, then
  columns of up to three stacked tiles, scrolling right inside
  `ScrollRow.scroll_row/1`, ending in a See all tile when the shelf has a
  page of its own (`SeeAllTile`). The See all tile takes the slot after the
  last tile, so it shares a column when one has room and starts a column of
  its own after a full one (`columns/2`).

  Widths come from the row's width, not from fixed card sizes:
  `column = (row − 2 × gap) ÷ (ratio + 1 + peek)` and `lead = ratio ×
  column` (`.row-scroll-marquee` in `app.css`, container query units on
  `.marquee`), so the lead tile and the first column fill the row the way a
  two-column grid would, with a quarter of the next column showing as the
  sign that the shelf scrolls. The last column grows into free width, so a
  marquee that fits ends flush.

  The marquee draws what it is given and caps nothing; the caller decides
  how many items to pass. Home's Coming Up is the first user
  (`HomeLive.Logic.coming_up_items/2`, up to 10 shows).

  A tile opens the title detail in place (UIDR-043): `select_entity` when
  the item has a library entity, else `open_title` by its TMDB ref — the
  host (`Live.TitleDetailHost`) answers both. Keyboard and gamepad move by
  screen position (the SHELF context's geometry), so up and down move
  within a column and right reaches the next one.
  """

  use Phoenix.Component

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
end
