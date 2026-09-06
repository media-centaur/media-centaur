defmodule MediaCentaurWeb.Components.HeroBackdrop do
  @moduledoc """
  The page hero backdrop: a `<canvas>` the `HeroBackdrop` hook paints from
  the decoded-bitmap cache in `app.js` (`assets/js/hooks/hero_backdrop.js`).

  Home's backdrop and the Library and Incoming atmosphere bands all render
  through this. The cache lives in JavaScript and survives live navigation,
  so a return to a page draws the 4K master in the mount frame instead of
  re-decoding it — the `<img>` it replaces was decoded again on every
  visit, and Chromium painted the page without it in the meantime.

  `data-src` is the cache key. It is `LiveHelpers.hero_backdrop_src/1` of
  the backdrop URL — the same function `ArtworkWarmup` uses for the root
  layout's marked prefetch hints, which `app.js` pre-decodes at idle. Any
  difference between the two is a cache miss, so neither side may derive
  the URL on its own.

  The host wraps this in its own positioned container (`.page-backdrop`,
  `.page-atmosphere`); the page CSS sizes the canvas exactly as it sized
  the image, since both are replaced elements.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "A bare canvas painted by a JS hook from a runtime bitmap cache; in isolation it renders nothing, so there is no state to catalog."

  use Phoenix.Component
  import MediaCentaurWeb.LiveHelpers, only: [hero_backdrop_src: 1]

  attr :backdrop_url, :string,
    required: true,
    doc: "the entity's `/media-images/…/backdrop.jpg` URL; the component sizes it (the master)"

  attr :id, :string, default: "hero-backdrop", doc: "hook element id; one hero slot per page"

  def hero_backdrop(assigns) do
    ~H"""
    <canvas
      id={@id}
      phx-hook="HeroBackdrop"
      data-src={hero_backdrop_src(@backdrop_url)}
      aria-hidden="true"
    ></canvas>
    """
  end
end
