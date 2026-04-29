defmodule MediaCentarrWeb.Components.HeroCard do
  @moduledoc """
  Full-bleed hero card for the Home page. One large title with backdrop,
  meta line, overview, and Play / Details actions.

  Item is an `Item` struct (see below). All fields except `:id`, `:name`,
  `:play_url`, and `:detail_url` may be nil — the template hides absent
  ones.
  """
  use Phoenix.Component
  import MediaCentarrWeb.CoreComponents, only: [icon: 1]

  defmodule Item do
    @moduledoc "View-model for the HeroCard."
    @enforce_keys [
      :id,
      :name,
      :year,
      :runtime,
      :genre_label,
      :overview,
      :backdrop_url,
      :play_url,
      :detail_url
    ]
    defstruct [
      :id,
      :name,
      :year,
      :runtime,
      :genre_label,
      :overview,
      :backdrop_url,
      :play_url,
      :detail_url
    ]

    @type t :: %__MODULE__{
            id: term(),
            name: String.t(),
            year: String.t() | nil,
            runtime: String.t() | nil,
            genre_label: String.t() | nil,
            overview: String.t() | nil,
            backdrop_url: String.t() | nil,
            play_url: String.t(),
            detail_url: String.t()
          }
  end

  attr :item, :any, required: true, doc: "an `Item.t()` or nil"

  def hero_card(assigns) do
    ~H"""
    <section
      :if={@item}
      data-component="hero"
      class="hero-fluid relative overflow-hidden bg-base-300"
    >
      <img
        :if={@item.backdrop_url}
        src={@item.backdrop_url}
        class="absolute inset-0 w-full h-full object-cover object-top"
      />
      <%!-- Two-axis gradient: vertical anchors lower 70% in dark, horizontal
            darkens the left third where the title sits. Sky-heavy backdrops
            need both axes — single-axis fades leave the upper band too bright. --%>
      <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/50 to-transparent"></div>
      <div class="absolute inset-0 bg-gradient-to-r from-black/55 via-transparent to-transparent">
      </div>
      <%!-- Fade-to-base bottom strip: blends the hero into the row container
            below it so the first row appears to emerge from the billboard. --%>
      <div class="absolute inset-x-0 bottom-0 h-32 hero-fade-bottom"></div>
      <div class="absolute inset-x-0 bottom-0 px-12 lg:px-16 pb-12 max-w-3xl flex flex-col gap-3">
        <div
          :if={@item.year || @item.runtime || @item.genre_label}
          class="text-sm text-white/80 flex flex-wrap gap-2"
        >
          <span :if={@item.year}>{@item.year}</span>
          <span :if={@item.year && @item.genre_label} class="text-white/40">·</span>
          <span :if={@item.genre_label}>{@item.genre_label}</span>
          <span :if={(@item.year || @item.genre_label) && @item.runtime} class="text-white/40">
            ·
          </span>
          <span :if={@item.runtime}>{@item.runtime}</span>
        </div>
        <h1 class="text-4xl sm:text-5xl lg:text-6xl font-bold text-white drop-shadow leading-[1.05] tracking-tight">
          {@item.name}
        </h1>
        <p
          :if={@item.overview}
          class="text-white/85 max-w-2xl text-base lg:text-lg leading-relaxed line-clamp-3"
        >
          {@item.overview}
        </p>
        <div class="flex gap-3 mt-2">
          <.link navigate={@item.play_url} class="btn btn-primary btn-lg">
            <.icon name="hero-play-mini" class="size-5" /> Play
          </.link>
          <.link navigate={@item.detail_url} class="btn btn-soft btn-primary btn-lg">
            <.icon name="hero-information-circle-mini" class="size-5" /> Details
          </.link>
        </div>
      </div>
    </section>
    """
  end
end
