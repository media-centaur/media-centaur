defmodule MediaCentaurWeb.Components.Detail.TitleLayer do
  @moduledoc """
  The 21:9 identity frame every cinematic surface seats its title in —
  logo PNG when the title has one, logotype text fallback, optional
  tagline, all shadowed for legibility over the panel-level backdrop
  (UIDR-011). With no backdrop behind it (`placeholder?`), the frame
  fills with the quiet film-icon placeholder instead.

  Extracted from `Detail.Hero` so the plan modal's movie confirm wears
  the *same* title layer instead of a hand-kept copy; `Hero` remains the
  owned-entity wrapper that derives these primitives from the entity's
  image records.
  """

  use MediaCentaurWeb, :html

  attr :title, :string, required: true
  attr :logo_url, :string, default: nil, doc: "logo image URL; nil falls back to the title text."
  attr :tagline, :string, default: nil, doc: "italic line under the title; blank/nil drops it."

  attr :placeholder?, :boolean,
    default: false,
    doc: "no panel-level backdrop behind the frame — render the glass film-icon placeholder."

  slot :actions, doc: "top-right overlay actions (tracking bell, etc.)"

  def title_layer(assigns) do
    ~H"""
    <div class={["aspect-[21/9] relative", @placeholder? && "glass-inset overflow-hidden"]}>
      <div :if={@placeholder?} class="w-full h-full flex items-center justify-center">
        <.icon name="hero-film" class="size-12 text-base-content/20" />
      </div>
      <div :if={@actions != []} class="absolute top-3 right-3 flex items-center gap-1">
        {render_slot(@actions)}
      </div>
      <div class="absolute bottom-4 left-6 right-6 space-y-1.5">
        <img
          :if={@logo_url}
          src={@logo_url}
          alt={@title}
          title={@title}
          class="max-h-20 max-w-[70%] object-contain text-on-image-lg"
          loading="eager"
          decoding="sync"
        />
        <h2 :if={!@logo_url} class="text-2xl font-bold leading-snug text-white text-on-image-lg">
          {@title}
        </h2>
        <p :if={@tagline && @tagline != ""} class="italic text-sm text-white/85 text-on-image">
          {@tagline}
        </p>
      </div>
    </div>
    """
  end
end
