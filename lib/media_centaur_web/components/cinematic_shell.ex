defmodule MediaCentaurWeb.Components.CinematicShell do
  @moduledoc """
  The cinematic modal frame — the tenant-agnostic half of the detail-modal
  technology (2026-08-05 sticky-orientation design), extracted so every
  modal grounded in a presentable subject can wear it: the library detail
  panel, the acquisition plan modal, the Downloads title modal, the
  pursuit modal.

  Owns the geometry machinery and nothing about the subject:

    * the always-in-DOM `<.modal>` wrapper — every shell panel carries
      `modal-panel--cinematic` (content-fit panels center with an
      upward optical bias), plus `modal-panel--full` (top-anchored,
      constant backdrop box) when the tenant says the document scrolls;
    * the panel-fixed backdrop image + atmosphere scrim
      (`CinematicBackdrop.backdrop/1`, `.modal-page-atmosphere`);
    * the single scrollport (`.modal-detail-scroll` + `DetailScrollGeometry`);
    * the transparent 21:9 hero window the fixed backdrop shows through
      (with the quiet placeholder when there is no artwork);
    * the sticky orientation block wrapper (`.detail-orientation`) and its
      `.orientation-backing*` replica of the backdrop;
    * the body sheet (`.detail-content-sheet` + `DetailBodyScroll`).

  Tenants supply the content through slots: `:hero_corner` (the social
  capsule in the hero window's upper right), `:orientation`
  (identity lockup, metadata, controls — the block that pins),
  `:body` (the scrolling document below) and `:foot` (a band of actions at
  the panel's bottom edge, outside the scroll — the plan modal's Cancel,
  Download and Approve; empty for the title detail and the pursuit window).

  The frame's geometry holds still while the body changes: the backdrop
  box is the constant `--modal-panel-h × 0.7` on every panel (the box the
  orientation backing replicates), never a share of the panel's height, so
  a disclosure opening or a row arriving clips more or less of the same
  picture and re-crops nothing (`app.css`, "The backdrop box is a
  constant").

  **The byte-identity invariant is structural here.** The panel backdrop
  and the orientation backing render the *same* `<img>` src (both through
  `sized_image_url(url, :full_bleed)`), from the single `backdrop_url`
  attr — the pinned-block illusion breaks the moment the two requests
  differ, which is why no tenant ever renders either copy itself.

  The `detail-*` / `orientation-*` / `modal-page-*` CSS families in
  `app.css` belong to this frame. Hook elements derive unique DOM ids
  from `id` (`<id>-scrollport`, `<id>-content`) so multiple frames can
  coexist in one DOM (e.g. plan modal + title modal on Downloads).
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaurWeb.Components.Detail.CinematicBackdrop

  attr :id, :string, required: true
  attr :open, :boolean, default: false

  attr :dismiss, :atom,
    values: [:ephemeral, :persistent],
    required: true,
    doc: "forwarded to `<.modal>` — see its moduledoc for the two kinds."

  attr :on_close, :string, default: nil

  attr :present, :boolean,
    default: false,
    doc:
      "whether a subject is loaded. The cinematic document (backdrop, scrollport, " <>
        "orientation block, body) renders only when true; the bare modal shell stays " <>
        "in the DOM either way so the blur compositing layer keeps warm."

  attr :backdrop_url, :string,
    default: nil,
    doc:
      "single source for BOTH backdrop copies (panel-fixed image and orientation " <>
        "backing replica). `nil` renders the quiet placeholder in the hero window " <>
        "instead — unavailable storage, artwork not yet scraped, or a subject with " <>
        "no backdrop."

  attr :full, :boolean,
    default: true,
    doc:
      "whether the document scrolls (`.modal-panel--full`: constant backdrop box, " <>
        "top-anchored panel). `false` gives the content-fit panel used by bare " <>
        "movies — centered with an upward optical bias (`.modal-panel--cinematic`)."

  attr :scroll_key, :string,
    default: nil,
    doc:
      "document identity for `DetailBodyScroll`'s per-view scroll memory — a new key " <>
        "is a new document and resets remembered offsets."

  attr :view_key, :atom,
    default: nil,
    doc: "current sub-view, keying the body's remembered scroll offset."

  attr :scroll_to_resume, :boolean,
    default: false,
    doc:
      "server-side signal that the body should open centred on its " <>
        "`[data-resume-target]` row — see `DetailBodyScroll`."

  attr :rest, :global, doc: "forwarded to the modal backdrop (nav wiring: `data-nav-overlay` etc.)."

  slot :hero_corner,
    doc: "sits in the hero window's upper right, over the orientation block — the social capsule."

  slot :orientation,
    doc: "content of the pinned block — identity lockup, metadata, controls."

  slot :body,
    doc: "the scrolling document below the orientation block. Omit for content-fit panels."

  slot :foot,
    doc:
      "the tenant's actions, as a band at the panel's bottom edge outside the scroll " <>
        "(`.modal-foot`): it sits under the document while the panel is content-fit and " <>
        "pins there once the body overflows. The tenant's root carries the band's " <>
        "`data-nav-zone`. The plan modal fills it on every stage; the title detail and " <>
        "the pursuit window leave it empty."

  def cinematic_shell(assigns) do
    assigns = assign(assigns, :placeholder?, assigns.present && is_nil(assigns.backdrop_url))

    ~H"""
    <.modal
      id={@id}
      open={@open}
      dismiss={@dismiss}
      on_close={@on_close}
      panel_class={
        if @present && @full,
          do: "modal-panel--cinematic modal-panel--full",
          else: "modal-panel--cinematic"
      }
      {@rest}
    >
      <%= if @present do %>
        <%!-- Fixed cinematic stage (2026-08-05 sticky-orientation design):
              the backdrop pins to the panel, BEHIND the transparent
              scroll surface, so it never moves while the document —
              atmosphere scrim included — scrolls over it. The image
              extends under the reserved scrollbar gutter, so the rail
              blends into the picture instead of cutting it off. --%>
        <CinematicBackdrop.backdrop backdrop_url={@backdrop_url} />
        <%!-- The panel-bottom fade: finishes the backdrop's dissolve at the
              panel's own edge when the panel is shorter than the constant
              backdrop box. Painted after the backdrop and BEFORE the
              atmosphere, so the scrim dims it like everything under it and
              a short panel's foot reads no lighter than its rows. --%>
        <div class="modal-page-bottom-fade z-0" aria-hidden="true"></div>
        <%!-- Atmosphere scrim is panel-fixed like the backdrop: the pinned
              orientation block's backing replicates it verbatim, and that
              replica only equals the real thing at every scroll depth if
              the real thing never moves. --%>
        <div class="modal-page-atmosphere z-0" aria-hidden="true"></div>
        <%!-- Single scroll surface for the entire document. Only the
              content (and its sheet) scrolls; backdrop and atmosphere
              stay put. .modal-detail-scroll owns the rail treatment:
              stable gutter, track painted to the shim tone. --%>
        <div
          id={"#{@id}-scrollport"}
          phx-hook="DetailScrollGeometry"
          class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative z-[1] modal-detail-scroll"
        >
          <div class="modal-page-content">
            <div class="relative z-[2]">
              <div class="detail-panel">
                <%!-- Hero window: transparent 21:9 frame the fixed
                      panel-level backdrop shows through. Panel-wide — it
                      bleeds under the reserved scrollbar rail like the
                      backdrop it frames (`.detail-hero`), so its right
                      edge is the panel's. Scrolls away; the orientation
                      block below overlaps its lower edge at rest and pins
                      to the scrollport top. Fills with the quiet
                      placeholder when there is no backdrop. --%>
                <div class="detail-hero relative">
                  <div class={[
                    "aspect-[21/9] relative",
                    @placeholder? && "glass-inset overflow-hidden"
                  ]}>
                    <div :if={@placeholder?} class="w-full h-full flex items-center justify-center">
                      <.icon name="hero-film" class="size-12 text-base-content/20" />
                    </div>
                  </div>
                  <%!-- Outside the frame, which clips when it is the
                        placeholder, and above the orientation block
                        (`.detail-hero-corner`), so what the corner opens
                        can hang down over it. --%>
                  <div :if={@hero_corner != []} class="detail-hero-corner">
                    {render_slot(@hero_corner)}
                  </div>
                </div>
                <%!-- Orientation block: pinned as one unit once scrolled to
                      the top. Must be a direct child of .detail-panel — a
                      wrapper that ends before the content sheet would
                      release the sticky early. --%>
                <div class="detail-orientation" data-role="detail-orientation">
                  <%!-- Opaque backing while pinned: clip window + a real
                        <img> clone of the panel backdrop in an identical
                        box, so both copies go through the same object-fit
                        rendering path and cannot drift. Fade and dim layers
                        replicate what the panel paints over the backdrop. --%>
                  <div class="orientation-backing" aria-hidden="true">
                    <img
                      :if={@backdrop_url}
                      class="orientation-backing-image"
                      src={sized_image_url(@backdrop_url, :full_bleed)}
                      alt=""
                      loading="eager"
                      decoding="sync"
                    />
                    <div class="orientation-backing-fade"></div>
                    <div class="orientation-backing-dim"></div>
                    <%!-- Replica of the content sheet, translated with the
                          scroll so the darkening appears to slide up behind
                          the lockup while the rows vanish below. --%>
                    <div class="orientation-backing-sheet"></div>
                  </div>
                  {render_slot(@orientation)}
                </div>
                <div
                  :if={@body != []}
                  id={"#{@id}-content"}
                  data-role="detail-content"
                  class="detail-content-sheet px-4 pb-5"
                  phx-hook="DetailBodyScroll"
                  data-scroll-key={@scroll_key}
                  data-view={@view_key}
                  data-scroll-to-resume={@scroll_to_resume || nil}
                >
                  {render_slot(@body)}
                </div>
              </div>
            </div>
          </div>
        </div>
        <%!-- The foot: a flex-none band after the scrollport, so a tenant's
              actions sit at the panel's bottom edge whatever the body's
              height, and pin there once it overflows. Its tone is the
              sheet's plateau (`.modal-foot`). --%>
        <div :if={@foot != []} class="modal-foot">
          {render_slot(@foot)}
        </div>
      <% end %>
    </.modal>
    """
  end
end
