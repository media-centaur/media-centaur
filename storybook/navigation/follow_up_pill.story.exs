defmodule MediaCentaurWeb.Storybook.Navigation.FollowUpPill do
  @moduledoc """
  The sidebar follow-up pill (UIDR-030) — a count of items waiting on the
  user, one primary variant for every entry that has a source; red stays
  with the condition dot. Zero renders nothing. Placement and size against
  the icon are a CSS rule on the rail itself, so this story shows the
  element; see the sidebar link story for it in place.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.FollowUpPill.follow_up_pill/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :one,
        description: "One item waiting.",
        attributes: %{id: "pill-one", count: 1}
      },
      %Variation{
        id: :many,
        description: "A larger count keeps the same size; the pill widens.",
        attributes: %{id: "pill-many", count: 12}
      },
      %Variation{
        id: :zero,
        description: "Nothing waiting renders nothing — silence is the healthy state.",
        attributes: %{id: "pill-zero", count: 0}
      }
    ]
  end
end
