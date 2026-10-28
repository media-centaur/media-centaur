defmodule MediaCentaurWeb.Components.FollowUpPill do
  @moduledoc """
  The sidebar follow-up pill (UIDR-030): a count of items on that page
  waiting on a decision from the user. One variant, one size, one
  placement rule. Renders nothing at zero — silence is the healthy
  state. It persists until the items are handled, and each source
  defines handling: approve or discard a plan, review a file, look at
  an incident (the Status source's seen-marker is its definition).

  Placement and size are one CSS rule (`.sidebar-follow-up`): a 14px chip
  at the link box's top-right corner in the 52px rail, overlapping only
  the icon's corner. The condition dot sits at the icon's bottom-right so
  the two never overlap. The pill is primary, not error: a count waiting
  on a decision is a call to act, and red is kept for the dot, which means
  something is wrong (UIDR-030, 2026-10-28 amendment).
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
      variant="primary"
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
