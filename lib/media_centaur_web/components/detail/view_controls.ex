defmodule MediaCentaurWeb.Components.Detail.ViewControls do
  @moduledoc """
  The modal's view controls — a soft button and a Manage cog, sharing Play's
  line.

  ## One control, named for where it goes

  Where the button leads is decided by `Logic.secondary_view/2`; this module
  only turns that destination into a label and a glyph:

  | destination | reads | glyph |
  |---|---|---|
  | `:main` | `Logic.body_label/1` — *Episodes*, *Movies*, *Extras* | list |
  | `:credits` | *More info* | info |
  | `nil` | nothing — Play's line carries only the cog | — |

  It is never labelled *Back*. "Episodes" says where you are going; "Back"
  only says it is not here, and what it means depends on which view you
  happen to be in. The destination is not always the body, which is exactly
  why the label has to follow it: a movie with no extras opens *on* More
  info, so Manage returns there and the control reads "More info".

  One control, in one slot. Until 2026-08-07 there were two, each
  relabelling itself to "Back" when its own view was open, so the word moved
  between the second and third slot depending on which sub-view was showing
  and no position in the row meant one thing.

  A tab strip was tried in between and reverted: it spans the panel and
  lands a band of chrome on the exact seam the eye crosses going from Play
  to the episode list, which is the worst place in the modal to put
  anything.

  ## Manage

  A quiet icon button, last, carrying `aria-pressed` rather than a label
  change — so the row's text never shifts. Files, external ids, rematch,
  refresh artwork: work a title needs once, not a third thing to do with
  it. Reachable from the couch because it is a `data-nav-item` of the
  enclosing `detail_actions` zone (UIDR-019); the hero's icon cluster, the
  other place it could live, is mouse-only.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Detail.Logic

  attr :entity, :map,
    required: true,
    doc:
      "entity-map from `MediaCentaur.Library.Views.DetailItem.to_entity_map/1`. Read only for `:type` and `:extras`, via `Detail.Logic`, to decide which control belongs here."

  attr :detail_view, :atom,
    required: true,
    doc: "the showing view — `:main`, `:credits` or `:info`."

  def view_controls(assigns) do
    assigns = assign(assigns, :destination, Logic.secondary_view(assigns.entity, assigns.detail_view))

    ~H"""
    <.view_button
      :if={@destination == :main}
      view="main"
      icon="hero-bars-3-bottom-left-mini"
    >
      {Logic.body_label(@entity)}
    </.view_button>
    <.view_button :if={@destination == :credits} view="credits" icon="hero-information-circle-mini">
      More info
    </.view_button>
    <.button
      variant="dismiss"
      size="sm"
      shape="circle"
      class="ml-1 opacity-60 hover:opacity-100 transition-opacity"
      phx-click="select_detail_view"
      phx-value-view={if @detail_view == :info, do: "main", else: "info"}
      data-role="manage-toggle"
      data-nav-item
      tabindex="0"
      aria-pressed={to_string(@detail_view == :info)}
      aria-label="Manage"
      title="Manage"
    >
      <.icon name="hero-cog-6-tooth-mini" class="size-5" />
    </.button>
    """
  end

  attr :view, :string, required: true, doc: "`detail_view` this button selects, as a URL value."
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp view_button(assigns) do
    ~H"""
    <.button
      variant="secondary"
      size="sm"
      phx-click="select_detail_view"
      phx-value-view={@view}
      data-role="view-control"
      data-nav-item
      tabindex="0"
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.button>
    """
  end
end
