defmodule MediaCentaurWeb.Components.HeroCard do
  @moduledoc """
  Full-bleed hero card for an assembled page: one large title with its
  backdrop (painted by the page), lockup or name, meta line, overview, and
  the page's actions in the `actions` slot — Home's Play and More info,
  Discovery's Add to watchlist, Download and More info. One card, two
  pages (UIDR-010 and UIDR-033, amended 2026-11-01).

  Item is an `Item` struct (see below): a library entity (`entity_id`) on
  Home, a TMDB identity (`ref`) on Discovery. Every field but `:id` and
  `:name` may be nil — the template hides absent ones.
  """

  use Phoenix.Component
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  # The lockup logo is capped at `max-w-md` (448 CSS px), which doubles on a
  # 4K panel. The card's backdrop is painted by the page, not here.

  defmodule Item do
    @moduledoc "View-model for the HeroCard: a library entity (`entity_id`) or a TMDB identity (`ref`)."
    @enforce_keys [
      :id,
      :name,
      :year,
      :runtime,
      :genre_label,
      :overview,
      :backdrop_url,
      :logo_url
    ]
    defstruct [
      :id,
      :entity_id,
      :ref,
      :name,
      :year,
      :runtime,
      :genre_label,
      :overview,
      :backdrop_url,
      :logo_url
    ]

    @type t :: %__MODULE__{
            id: term(),
            entity_id: String.t() | nil,
            ref: {pos_integer(), :movie | :tv_series} | nil,
            name: String.t(),
            year: String.t() | nil,
            runtime: String.t() | nil,
            genre_label: String.t() | nil,
            overview: String.t() | nil,
            backdrop_url: String.t() | nil,
            logo_url: String.t() | nil
          }
  end

  attr :item, :any, required: true, doc: "an `Item.t()` or nil"

  slot :actions,
    required: true,
    doc:
      "the card's buttons, each a nav item: Home's Play and More info; Discovery's Add to watchlist, Download and More info"

  def hero_card(assigns) do
    ~H"""
    <section
      :if={@item}
      data-component="hero"
      class="hero-fluid relative flex flex-col justify-center px-12 lg:px-16 py-12 max-compact:px-6 max-compact:py-8"
    >
      <%!-- No own scrims: page-level atmosphere (`.page-side-dim` in
            HomeLive) provides both the vertical fade-to-constant-dim and
            the left-side darkening, so the effect doesn't end at the
            hero's edge.

            Content sits in normal flow (not absolutely positioned) so its
            intrinsic height is the hero's true minimum — a scrunched
            viewport grows the section rather than bleeding the CTAs under
            the next row. py-12 outlasts the content wrapper's -mt-8
            overlap in HomeLive. --%>
      <div class="max-w-2xl flex flex-col gap-3">
        <%!-- Logo replaces the title text when present. The PNG is sized by
              max-height (preserves aspect) and capped on width so very wide
              logos don't push past the hero's text column. --%>
        <img
          :if={@item.logo_url}
          src={sized_image_url(@item.logo_url, 960)}
          alt={@item.name}
          class="max-h-44 max-w-md object-contain object-left text-on-image-lg max-compact:max-h-28 max-compact:max-w-full"
        />
        <h1
          :if={!@item.logo_url}
          class="text-5xl sm:text-6xl lg:text-7xl font-bold text-white text-on-image-lg leading-[1.05] tracking-tight max-compact:text-4xl"
        >
          {@item.name}
        </h1>
        <div
          :if={@item.year || @item.runtime || @item.genre_label}
          class="text-base text-white/80 flex flex-wrap gap-2 text-on-image"
        >
          <span :if={@item.year}>{@item.year}</span>
          <span :if={@item.year && @item.genre_label} class="text-white/40">·</span>
          <span :if={@item.genre_label}>{@item.genre_label}</span>
          <span :if={(@item.year || @item.genre_label) && @item.runtime} class="text-white/40">
            ·
          </span>
          <span :if={@item.runtime}>{@item.runtime}</span>
        </div>
        <p
          :if={@item.overview}
          class="text-white/85 max-w-2xl text-lg lg:text-xl leading-relaxed line-clamp-5 text-on-image max-compact:text-base max-compact:line-clamp-3"
        >
          {@item.overview}
        </p>
        <%!-- The page's actions, each a focusable nav item: Left/Right moves
              between them, Select activates the focused one; the hero zone's
              entry anchor is the first. --%>
        <div class="flex gap-3 mt-2">
          {render_slot(@actions)}
        </div>
      </div>
    </section>
    """
  end
end
