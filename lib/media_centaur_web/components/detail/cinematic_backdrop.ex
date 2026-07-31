defmodule MediaCentaurWeb.Components.Detail.CinematicBackdrop do
  @moduledoc """
  The detail modal's cinematic page structure, extracted so more than one
  surface can wear it: a full-width backdrop that fades into `base-100`
  (`.modal-page-backdrop`) plus a left-weighted vertical scrim
  (`.modal-page-atmosphere`), with the caller's content layered on top at
  `z-[2]`.

  Shared by `ModalShell` (the owned-entity detail panel) and the
  acquisition plan modal's movie-confirm preview, so a just-picked movie
  reads as the same cinematic surface as one already in the library — the
  difference being only where the backdrop URL points (local
  `/media-images` for owned artwork, a TMDB hotlink for a not-yet-owned
  preview).

  Renders as a **fragment** — a `.modal-page-backdrop` sibling followed by
  the `.modal-page-content` wrapper — with no positioning root of its own.
  The caller's scroll container is the positioning context and **must be
  `position: relative`**; keeping the backdrop absolute inside that
  scroller is what lets it scroll with the content instead of pinning to
  the viewport (see the `.modal-page-*` rules in `app.css`).
  """

  use MediaCentaurWeb, :html

  attr :backdrop_url, :string,
    default: nil,
    doc:
      "absolute image URL painted behind the content (local `/media-images/…` or a TMDB hotlink). `nil` renders the atmosphere scrim alone — no backdrop image."

  attr :early_fade, :boolean,
    default: false,
    doc:
      "fade the backdrop into `base-100` high up (`--early-fade`) — for work surfaces " <>
        "(pickers, boards, the pursuit detail) where the image is a header treatment, not " <>
        "a hero. Default keeps the tall fade for hero layers (detail panel, movie confirm)."

  slot :inner_block, required: true

  def cinematic_backdrop(assigns) do
    ~H"""
    <div
      :if={@backdrop_url}
      class={["modal-page-backdrop", @early_fade && "modal-page-backdrop--early-fade"]}
      aria-hidden="true"
    >
      <img src={@backdrop_url} alt="" loading="eager" decoding="sync" fetchpriority="high" />
    </div>

    <div class="modal-page-content">
      <div class="modal-page-atmosphere" aria-hidden="true"></div>

      <div class="relative z-[2]">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
