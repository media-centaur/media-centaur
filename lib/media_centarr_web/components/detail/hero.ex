defmodule MediaCentarrWeb.Components.Detail.Hero do
  @moduledoc """
  21:9 detail-panel hero with backdrop image, logo overlay (or title fallback),
  optional tagline, and a top-right `actions` slot for things like the
  release-tracking bell.

  Type-agnostic — takes an `entity` for image lookup and name fallback only.
  """
  use MediaCentarrWeb, :html

  import MediaCentarrWeb.LiveHelpers, only: [image_url: 2]

  attr :entity, :map, required: true
  attr :tagline, :string, default: nil
  attr :available, :boolean, default: true
  slot :actions, doc: "top-right overlay actions (tracking bell, etc.)"

  def hero(assigns) do
    backdrop = image_url(assigns.entity, "backdrop")
    background = backdrop || image_url(assigns.entity, "poster")
    logo = image_url(assigns.entity, "logo")

    assigns =
      assigns
      |> assign(:background, background)
      |> assign(:logo, logo)

    ~H"""
    <div class="detail-hero relative overflow-hidden">
      <div class="aspect-[21/9] glass-inset relative">
        <img
          :if={@background && @available}
          src={@background}
          class="w-full h-full object-cover object-top"
        />
        <div
          :if={@background && !@available}
          class="w-full h-full bg-base-content/5"
          aria-label="Artwork unavailable — storage not mounted"
        />
        <div :if={!@background} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>
        <div class="absolute inset-0 bg-gradient-to-t from-base-100 via-base-100/60 via-30% to-transparent" />
        <div :if={@actions != []} class="absolute top-3 right-3 flex items-center gap-1">
          {render_slot(@actions)}
        </div>
        <div class="absolute bottom-4 left-4 right-4 space-y-1">
          <img
            :if={@logo && @available}
            src={@logo}
            class="max-h-16 max-w-[80%] object-contain drop-shadow-[0_2px_12px_rgba(0,0,0,0.7)]"
          />
          <h2
            :if={!@logo || !@available}
            class="text-xl font-bold leading-snug drop-shadow-[0_2px_8px_rgba(0,0,0,0.7)]"
          >
            {@entity.name}
          </h2>
          <p
            :if={@tagline && @tagline != ""}
            class="italic text-sm text-base-content/80 drop-shadow-[0_2px_6px_rgba(0,0,0,0.7)]"
          >
            {@tagline}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
