defmodule MediaCentarrWeb.Components.HeroCard do
  @moduledoc """
  Full-bleed hero card for the Home page. One large title with backdrop,
  meta line, overview, and Play / More info actions.

  Item is an `Item` struct (see below). All fields except `:id`, `:name`,
  `:play_url`, and `:detail_url` may be nil — the template hides absent
  ones.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :pending
  @storybook_reason "Phase 4 — see docs/superpowers/plans/2026-05-02-storybook-fleshout.md"

  use Phoenix.Component
  import MediaCentarrWeb.CoreComponents, only: [button: 1, icon: 1]

  defmodule Item do
    @moduledoc "View-model for the HeroCard."
    @enforce_keys [
      :id,
      :entity_id,
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
            entity_id: String.t(),
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

  def hero_card(assigns) do
    ~H"""
    <section
      :if={@item}
      data-component="hero"
      class="hero-fluid relative overflow-hidden"
    >
      <%!-- No own scrims: page-level atmosphere (`.page-side-dim` in
            HomeLive) provides both the vertical fade-to-constant-dim and
            the left-side darkening, so the effect doesn't end at the
            hero's edge. --%>
      <div class="absolute inset-y-0 left-0 px-12 lg:px-16 max-w-2xl flex flex-col justify-center gap-3">
        <%!-- Logo replaces the title text when present. The PNG is sized by
              max-height (preserves aspect) and capped on width so very wide
              logos don't push past the hero's text column. --%>
        <img
          :if={@item.logo_url}
          src={@item.logo_url}
          alt={@item.name}
          class="max-h-44 max-w-md object-contain object-left drop-shadow-lg"
        />
        <h1
          :if={!@item.logo_url}
          class="text-5xl sm:text-6xl lg:text-7xl font-bold text-white drop-shadow leading-[1.05] tracking-tight"
        >
          {@item.name}
        </h1>
        <div
          :if={@item.year || @item.runtime || @item.genre_label}
          class="text-base text-white/80 flex flex-wrap gap-2"
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
          class="text-white/85 max-w-2xl text-lg lg:text-xl leading-relaxed line-clamp-5"
        >
          {@item.overview}
        </p>
        <div class="flex gap-3 mt-2">
          <.button
            variant="primary"
            size="lg"
            phx-click="select_entity"
            phx-value-id={@item.entity_id}
            phx-value-autoplay="1"
          >
            <.icon name="hero-play-mini" class="size-5" /> Play
          </.button>
          <.button
            variant="secondary"
            size="lg"
            class="text-white"
            phx-click="select_entity"
            phx-value-id={@item.entity_id}
          >
            <.icon name="hero-information-circle-mini" class="size-5" /> More info
          </.button>
        </div>
      </div>
    </section>
    """
  end
end
