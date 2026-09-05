defmodule MediaCentaurWeb.Components.FollowUpPill do
  @moduledoc """
  The sidebar follow-up pill (UIDR-030): a count of items on that page
  waiting on a decision from the user. One variant, one size, one
  placement rule. Renders nothing at zero — silence is the healthy
  state. It persists until the items are handled, and each source
  defines handling: approve or discard a plan, review a file, look at
  an incident (the Status source's seen-marker is its definition).

  Placement is one CSS rule (`.sidebar-follow-up`) keyed off the rail's
  `--sidebar-expanded` switch: at the row's end when the rail is open,
  at the icon's top-right corner when it is the 52px rail, so the count
  survives both widths. The condition dot sits at the icon's
  bottom-right so the two never overlap.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [badge: 1]

  attr :count, :integer, required: true, doc: "items waiting on a decision; 0 renders nothing"
  attr :id, :string, required: true

  def follow_up_pill(assigns) do
    ~H"""
    <.badge
      :if={@count > 0}
      id={@id}
      variant="error"
      size="xs"
      class="sidebar-follow-up"
      data-component="follow-up-pill"
      aria-label={"#{@count} waiting for you"}
    >
      {@count}
    </.badge>
    """
  end
end
