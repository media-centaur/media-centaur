defmodule MediaCentaurWeb.Storybook.Navigation.FollowUpPill do
  @moduledoc """
  The sidebar follow-up pill (UIDR-030) — a count of items waiting on the
  user, one variant for every entry that has a source. Zero renders
  nothing. The two rail placements are a CSS switch on the rail itself,
  so this story shows the element; verify placement on the live sidebar.
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
