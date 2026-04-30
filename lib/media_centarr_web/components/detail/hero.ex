defmodule MediaCentarrWeb.Components.Detail.Hero do
  @moduledoc """
  21:9 detail-panel hero — a transparent positioning frame for the logo
  overlay (or title fallback), optional tagline, and a top-right `actions`
  slot for things like the release-tracking bell.

  The backdrop image and atmospheric scrims live at the modal-panel level
  (`ModalShell`), where they extend past this frame into the metadata
  region for a cinematic continuation. This component is purely the title
  layer that sits on top.

  Type-agnostic — takes an `entity` for image lookup and name fallback only.
  """
  use MediaCentarrWeb, :html

  import MediaCentarrWeb.LiveHelpers, only: [image_url: 2]

  attr :entity, :map,
    required: true,
    doc:
      "polymorphic library entity — Movie, TVSeries, MovieSeries, or VideoObject — with `:images` preloaded for `image_url/2` lookup. The component reads `:name` and image roles only, so the union is intentionally untyped at this layer; tightening to a typed Subject struct is deferred to Phase 5 when DetailPanel itself reshapes its assigns."

  attr :tagline, :string, default: nil
  attr :available, :boolean, default: true
  slot :actions, doc: "top-right overlay actions (tracking bell, etc.)"

  def hero(assigns) do
    backdrop = image_url(assigns.entity, "backdrop")
    background = backdrop || image_url(assigns.entity, "poster")
    logo = image_url(assigns.entity, "logo")
    show_placeholder? = !background || !assigns.available

    assigns =
      assigns
      |> assign(:logo, logo)
      |> assign(:show_placeholder?, show_placeholder?)

    ~H"""
    <div class="detail-hero relative">
      <div class={[
        "aspect-[21/9] relative",
        @show_placeholder? && "glass-inset overflow-hidden"
      ]}>
        <%!-- Empty state when artwork is missing or storage isn't mounted —
              ModalShell renders no panel-level backdrop in those cases, so
              we fill the 21:9 frame with a quiet placeholder. --%>
        <div :if={@show_placeholder?} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>
        <div :if={@actions != []} class="absolute top-3 right-3 flex items-center gap-1">
          {render_slot(@actions)}
        </div>
        <div class="absolute bottom-4 left-6 right-6 space-y-1.5">
          <img
            :if={@logo && @available}
            src={@logo}
            class="max-h-20 max-w-[70%] object-contain drop-shadow-[0_2px_14px_rgba(0,0,0,0.75)]"
          />
          <h2
            :if={!@logo || !@available}
            class="text-2xl font-bold leading-snug text-white drop-shadow-[0_2px_10px_rgba(0,0,0,0.85)]"
          >
            {@entity.name}
          </h2>
          <p
            :if={@tagline && @tagline != ""}
            class="italic text-sm text-white/85 drop-shadow-[0_2px_8px_rgba(0,0,0,0.8)]"
          >
            {@tagline}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
