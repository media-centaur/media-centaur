defmodule MediaCentaurWeb.Components.Detail.CinematicBackdrop do
  @moduledoc """
  The cinematic backdrop image layer — the full-width image that fades
  into `base-100` (`.modal-page-backdrop`, `app.css`).

  `CinematicShell` seats it directly in the modal panel, where it stays
  *fixed* while the detail document scrolls over it (2026-08-05
  sticky-orientation design). Every cinematic modal renders it through
  the frame; the old scrolls-with-content fragment this module used to
  carry lost its last consumer when the pursuit modal re-seated on the
  shell.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  attr :backdrop_url, :string,
    default: nil,
    doc:
      "absolute image URL painted behind the content (local `/media-images/…` or a TMDB " <>
        "hotlink). `nil` renders nothing — the frame shows its quiet hero-window " <>
        "placeholder instead."

  def backdrop(assigns) do
    ~H"""
    <div :if={@backdrop_url} class="modal-page-backdrop" aria-hidden="true">
      <%!-- `:full_bleed` is load-bearing: `.orientation-backing-image` in
            `CinematicShell` replicates this exact URL, and the pinned-block
            illusion breaks the moment the two requests differ. --%>
      <img
        src={sized_image_url(@backdrop_url, :full_bleed)}
        alt=""
        loading="eager"
        decoding="sync"
        fetchpriority="high"
      />
    </div>
    """
  end
end
