defmodule MediaCentaurWeb.Components.Detail.TitleLayer do
  @moduledoc """
  The identity lockup every cinematic surface seats its title in — logo
  PNG when the title has one, logotype text fallback, optional tagline,
  all shadowed for legibility over the panel-level backdrop (UIDR-011).

  Extracted so the plan modal's movie confirm wears the *same* lockup as
  the detail modal instead of a hand-kept copy. The 21:9 frame it is
  seated in belongs to `CinematicShell`, which owns the placeholder fill
  for a title with no backdrop; this module is the content alone, so a
  caller can seat it in the hero window or in normal flow.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  @doc """
  The identity lockup — logo PNG (or logotype text fallback) plus
  optional tagline, shadowed for legibility over imagery (UIDR-011).
  The detail panel's orientation block seats it in normal flow so it
  pins with the block on scroll; the plan modal seats it over its
  confirm artwork. One representation of the lockup, several seatings.
  """
  # Height-capped at `max-h-20` and bounded to 70% of the identity frame, so a
  # wide logo lands near 480 CSS px — doubled for a 4K panel.
  attr :title, :string, required: true
  attr :logo_url, :string, default: nil, doc: "logo image URL; nil falls back to the title text."
  attr :tagline, :string, default: nil, doc: "italic line under the title; blank/nil drops it."

  def lockup(assigns) do
    ~H"""
    <div class="space-y-1.5">
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
