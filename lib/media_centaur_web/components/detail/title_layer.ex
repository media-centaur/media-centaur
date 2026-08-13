defmodule MediaCentaurWeb.Components.Detail.TitleLayer do
  @moduledoc """
  The 21:9 identity frame every cinematic surface seats its title in —
  logo PNG when the title has one, logotype text fallback, optional
  tagline, all shadowed for legibility over the panel-level backdrop
  (UIDR-011). With no backdrop behind it (`placeholder?`), the frame
  fills with the quiet film-icon placeholder instead.

  Extracted so the plan modal's movie confirm wears the *same* title
  layer as the detail modal instead of a hand-kept copy; the hero window
  itself (the transparent 21:9 frame) belongs to `CinematicShell`.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  # Height-capped at `max-h-20` and bounded to 70% of the identity frame, so a
  # wide logo lands near 480 CSS px — doubled for a 4K panel.

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
      <div class="absolute bottom-4 left-6 right-6">
        <.lockup title={@title} logo_url={@logo_url} tagline={@tagline} />
      </div>
    </div>
    """
  end

  @doc """
  The identity lockup alone — logo PNG (or logotype text fallback) plus
  optional tagline, shadowed for legibility over imagery (UIDR-011).
  `title_layer/1` seats it bottom-left inside its 21:9 frame; the detail
  panel's orientation block seats it in normal flow so it pins with the
  block on scroll. One representation of the lockup, two seatings.
  """
  attr :title, :string, required: true
  attr :logo_url, :string, default: nil, doc: "logo image URL; nil falls back to the title text."
  attr :tagline, :string, default: nil, doc: "italic line under the title; blank/nil drops it."

  attr :eyebrow, :string,
    default: nil,
    doc:
      "small-caps context line above the title — the collection eyebrow of the movie-first modal (UIDR-023), e.g. \"Sample Saga · Part 2 of 4\". Blank/nil drops it."

  def lockup(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p
        :if={@eyebrow && @eyebrow != ""}
        class="text-[11px] uppercase tracking-[0.14em] text-white/70 text-on-image"
      >
        {@eyebrow}
      </p>
      <img
        :if={@logo_url}
        src={sized_image_url(@logo_url, 960)}
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
    """
  end
end
