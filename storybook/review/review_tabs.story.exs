defmodule MediaCentaurWeb.Storybook.Review.ReviewTabs do
  @moduledoc """
  Story for the review tab strip — the two review dimensions (identity /
  episode mapping) with their pending counts.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewTabs.review_tabs/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :identity_active,
        description: "On the identity page, work waiting on both dimensions",
        attributes: %{active: :identity, identity_count: 4, mapping_count: 2}
      },
      %Variation{
        id: :mapping_active,
        description: "On the episode-mapping page",
        attributes: %{active: :mapping, identity_count: 4, mapping_count: 2}
      },
      %Variation{
        id: :only_identity_work,
        description: "Zero-count tab drops its badge but stays reachable",
        attributes: %{active: :identity, identity_count: 3, mapping_count: 0}
      },
      %Variation{
        id: :only_mapping_work,
        description: "Only mapping work — how the strip looks landing on /reconcile",
        attributes: %{active: :mapping, identity_count: 0, mapping_count: 5}
      }
    ]
  end
end
