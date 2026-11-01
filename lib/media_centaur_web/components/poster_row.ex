defmodule MediaCentaurWeb.Components.PosterRow do
  @moduledoc """
  Horizontal poster row: Home's "Recently Added" and Discovery's shelves —
  and the **grouped row** (`grouped_poster_row/1`), one scroll row holding
  labelled groups of the same tiles with a hairline between them
  (Discovery's Watchlist shelf: In Theaters · Coming Up); one nav zone,
  an empty group omitted, the row gone when every group is empty.

  Cards are the shared 2:3 poster (`--card-poster-w`), so they are the same
  size as the library grid's — the row's "See all" lands on `/library`, and
  posters that resized across that step would read as two different objects.
  How many fit is left to `.row-scroll-poster`; the last one is deliberately
  cut off, which is what says the row scrolls. The track is a
  `ScrollRow.scroll_row/1`, which adds the mouse user's edge arrows.

  Each item is an `Item` struct (see below). `year` may be a string like
  "2023" or "S2 · 2026". A tile's subject is a library entity
  (`entity_id`, opened by `select_entity`, with the play overlay) or a
  TMDB identity (`ref`, opened by `open_title`, no Play: nothing to play),
  the two openings the title detail host already has. `marker` is the
  quiet state chip at the poster's foot, in `Title.Logic.row_markers/2`'s
  words; `chip` a date at the poster's head (an opening date, a release
  month); `glyphs` the title's social glyphs in a dark pill at the top
  right (`Title.SocialGlyph`, UIDR-049), each a flag at its grade;
  `slots` the title's toolbar (`Title.ToolbarSlots`): the bookmark, the
  one-click Download and Ignore in a strip at the poster's foot, revealed
  on hover, sending the title detail host's events by ref (UIDR-038 rule
  4, amended). A pointer affordance: the strip's buttons are not nav
  items, so a shelf's keyboard and gamepad path to the verbs stays the
  detail the tile opens. The row's `id` names the `ScrollRow`, and each tile's DOM id
  is derived from it, so one page may hold several rows and a title may
  sit on two of them.

  When `see_all_href` is set, a "See all" card renders as the last slot in
  the scrollable row, mirroring the Continue Watching row.
  """

  use Phoenix.Component
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [poster_src: 1]

  alias MediaCentaurWeb.Components.PlayOverlay
  alias MediaCentaurWeb.Components.ScrollRow
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.Components.Title.ToolbarSlots
  alias MediaCentaurWeb.TitleRef

  defmodule Item do
    @moduledoc """
    View-model for a single PosterRow card. The subject is one of
    `entity_id` (a library entity) or `ref` (a TMDB identity,
    `{tmdb_id, :movie | :tv_series}`). `available?` is whether the
    entry's media directory is reachable; an offline card renders a
    neutral block, the name, and no Play (the same treatment as the
    Library card). `marker` is the state chip, `chip` the date chip,
    `glyphs` the social glyphs (`%{flags, grades, tips}`, the attrs of
    `SocialGlyph.social_glyphs/1`), `slots` the toolbar's positions
    (`Title.ToolbarSlots`); each nil for none.
    """
    @enforce_keys [:id, :name, :year, :poster_url]
    defstruct [
      :id,
      :entity_id,
      :ref,
      :name,
      :year,
      :poster_url,
      :marker,
      :chip,
      :glyphs,
      :slots,
      available?: true
    ]

    @type glyphs :: %{flags: [atom()], grades: %{atom() => atom()}, tips: %{atom() => String.t()}}

    @type t :: %__MODULE__{
            id: term(),
            entity_id: String.t() | nil,
            ref: {pos_integer(), :movie | :tv_series} | nil,
            name: String.t(),
            year: String.t() | nil,
            poster_url: String.t() | nil,
            marker: String.t() | nil,
            chip: String.t() | nil,
            glyphs: glyphs() | nil,
            slots: ToolbarSlots.t() | nil,
            available?: boolean()
          }

    @doc "What the tile's DOM id and `data-entity-id` carry: the entity id, or the ref as a URL param."
    @spec key(t()) :: String.t()
    def key(%__MODULE__{entity_id: entity_id}) when is_binary(entity_id), do: entity_id
    def key(%__MODULE__{ref: {_tmdb_id, _media_type} = ref}), do: TitleRef.param(ref)
  end

  attr :id, :string, required: true, doc: "the row's DOM id; tile ids derive from it"
  attr :items, :list, required: true, doc: "list of `Item.t()`"

  attr :see_all_href, :string,
    default: nil,
    doc: "when set, renders a trailing \"See all\" card navigating to this path"

  attr :show_play_button, :boolean,
    default: true,
    doc:
      "When false, suppresses the hover play overlay (UIDR-027). Driven by the `card_play_button` Settings entry (see `MediaCentaur.Settings.Preferences.CardPlayButton`)."

  def poster_row(assigns) do
    ~H"""
    <ScrollRow.scroll_row :if={@items != []} id={@id} variant={:poster} data-component="poster-row">
      <.tile :for={item <- @items} row_id={@id} item={item} show_play_button={@show_play_button} />

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
    </ScrollRow.scroll_row>
    """
  end

  attr :id, :string, required: true, doc: "the row's DOM id; tile ids derive from it"

  attr :groups, :list,
    required: true,
    doc: "`%{label: String.t(), items: [Item.t()]}` in order; an empty group is omitted"

  attr :show_play_button, :boolean, default: true, doc: "as `poster_row/1`'s"

  @doc """
  One scroll row of labelled groups of poster tiles, a hairline between
  the groups: Discovery's Watchlist shelf (In Theaters · Coming Up). One
  nav zone; the items navigate by geometry across the groups.
  """
  def grouped_poster_row(assigns) do
    assigns = assign(assigns, :groups, Enum.reject(assigns.groups, &(&1.items == [])))

    ~H"""
    <ScrollRow.scroll_row
      :if={@groups != []}
      id={@id}
      variant={:poster}
      data-component="grouped-poster-row"
    >
      <div :for={group <- @groups} class="poster-group" data-group={group.label}>
        <span class="poster-group-label">{group.label}</span>
        <div class="poster-group-tiles">
          <.tile
            :for={item <- group.items}
            row_id={@id}
            item={item}
            show_play_button={@show_play_button}
          />
        </div>
      </div>
    </ScrollRow.scroll_row>
    """
  end

  attr :row_id, :string, required: true
  attr :item, Item, required: true
  attr :show_play_button, :boolean, required: true

  # A div, not a <button>: the play overlay nests a real button inside
  # (UIDR-027) and buttons cannot nest. Same pattern as the library
  # poster card.
  defp tile(assigns) do
    ~H"""
    <div
      id={"#{@row_id}-#{Item.key(@item)}"}
      phx-click={if @item.entity_id, do: "select_entity", else: "open_title"}
      phx-value-id={@item.entity_id}
      phx-value-ref={if is_nil(@item.entity_id), do: Item.key(@item)}
      class="card-hover play-overlay-host relative aspect-[2/3] rounded overflow-hidden glass-inset block w-full text-left"
      data-row-item
      data-nav-item
      data-entity-id={Item.key(@item)}
      tabindex="0"
    >
      <img
        :if={@item.available? && @item.poster_url}
        src={poster_src(@item.poster_url)}
        alt={@item.name}
        class="absolute inset-0 w-full h-full object-cover"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@item.available?}
        class="absolute inset-0 bg-base-content/5"
        aria-label="Artwork unavailable — storage not mounted"
      />
      <%!-- Fallback only when artwork is missing or offline — the poster
            image itself already carries the title, so showing it again is
            redundant. --%>
      <div
        :if={!@item.available? || !@item.poster_url}
        class={["absolute inset-x-2", if(@item.marker, do: "bottom-8", else: "bottom-2")]}
      >
        <div class="text-xs font-semibold text-white text-on-image truncate">{@item.name}</div>
        <div :if={@item.year} class="text-[10px] text-white/70 text-on-image">{@item.year}</div>
      </div>

      <span :if={@item.chip} class="poster-tile-chip">{@item.chip}</span>
      <SocialGlyph.social_glyphs
        :if={@item.glyphs && @item.glyphs.flags != []}
        flags={@item.glyphs.flags}
        grades={@item.glyphs.grades}
        tips={@item.glyphs.tips}
        class="poster-tile-glyphs"
      />
      <span :if={@item.marker} class="poster-tile-marker">{@item.marker}</span>

      <%!-- The toolbar's verbs in the tile's own form (the Feed row wears
            them labelled): tabindex -1 and no nav attribute, so the shelf's
            cursor passes over them and the keyboard's path is the detail. --%>
      <div :if={@item.slots} class="poster-tile-tools" data-role="toolbar">
        <button
          :if={@item.slots.list == :list}
          id={"#{@row_id}-#{Item.key(@item)}-list"}
          type="button"
          class="poster-tile-tool"
          tabindex="-1"
          phx-click="title_list"
          phx-value-ref={Item.key(@item)}
          aria-label="Add to watchlist"
          data-tip="Add to watchlist"
        >
          <.icon name="hero-bookmark" class="size-4" />
        </button>
        <button
          :if={@item.slots.list == :listed}
          id={"#{@row_id}-#{Item.key(@item)}-list"}
          type="button"
          class="poster-tile-tool poster-tile-tool-on"
          tabindex="-1"
          phx-click="title_list"
          phx-value-ref={Item.key(@item)}
          aria-label="Remove from watchlist"
          data-tip="On your watchlist"
        >
          <.icon name="hero-bookmark-solid" class="size-4" />
        </button>
        <span
          :if={@item.slots.list == :following}
          class="poster-tile-tool poster-tile-tool-on"
          aria-label="Tracking"
          data-tip="Tracking"
        >
          <.icon name="hero-bookmark-solid" class="size-4" />
        </span>
        <button
          :if={@item.slots.download == :download}
          id={"#{@row_id}-#{Item.key(@item)}-download"}
          type="button"
          class="poster-tile-tool"
          tabindex="-1"
          phx-click="title_download"
          phx-value-ref={Item.key(@item)}
          aria-label="Download"
          data-tip="Download"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" />
        </button>
        <button
          id={"#{@row_id}-#{Item.key(@item)}-ignore"}
          type="button"
          class="poster-tile-tool"
          tabindex="-1"
          phx-click="title_ignore"
          phx-value-ref={Item.key(@item)}
          aria-label="Ignore"
          data-tip="Ignore — hide from the Feed and Discovery"
        >
          <.icon name="hero-eye-slash" class="size-4" />
        </button>
      </div>

      <%!-- Offline storage cannot play (UIDR-027); a TMDB identity has
            nothing to play. --%>
      <PlayOverlay.play_overlay
        :if={@show_play_button && @item.available? && @item.entity_id}
        entity_id={@item.entity_id}
      />
    </div>
    """
  end
end
