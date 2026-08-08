defmodule MediaCentaurWeb.Components.Detail.Hero do
  @moduledoc """
  Detail-panel hero window — the transparent 21:9 frame at the top of the
  scroll document that lets the panel-level *fixed* backdrop show through
  (`ModalShell` pins `CinematicBackdrop.backdrop/1` to the panel; content
  scrolls over it).

  Carries only the top-right `actions` overlay (tracking bell) and the
  quiet placeholder frame when artwork is missing or storage is
  unmounted. The identity lockup, tagline, and progress hairline live in
  the orientation block below (`DetailPanel`), which overlaps this frame
  at rest and pins to the top of the scrollport on scroll — this window
  scrolls away, the orientation block does not.

  Type-agnostic — takes an `entity` for image lookup only.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [image_url: 2]

  attr :entity, :map,
    required: true,
    doc:
      "polymorphic entity-map from `MediaCentaur.Library.Views.DetailItem.to_entity_map/1`. Reads `:images` only, so the union stays untyped at this layer; tightening to a typed `DetailItem` attr is a Phase 3.3 follow-up (component-contracts campaign)."

  attr :available, :boolean, default: true

  slot :actions, doc: "top-right overlay actions (tracking bell, etc.)"

  def hero(assigns) do
    background = image_url(assigns.entity, "backdrop") || image_url(assigns.entity, "poster")
    assigns = assign(assigns, :show_placeholder?, !background || !assigns.available)

    ~H"""
    <div class="detail-hero relative">
      <div class={["aspect-[21/9] relative", @show_placeholder? && "glass-inset overflow-hidden"]}>
        <%!-- Empty state when artwork is missing or storage isn't
              mounted — ModalShell renders no panel-level backdrop in
              those cases, so this frame fills with the quiet
              placeholder instead of empty space. --%>
        <div :if={@show_placeholder?} class="w-full h-full flex items-center justify-center">
          <.icon name="hero-film" class="size-12 text-base-content/20" />
        </div>
        <div :if={@actions != []} class="absolute top-3 right-3 flex items-center gap-1">
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end
end
