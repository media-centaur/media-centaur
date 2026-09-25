defmodule MediaCentaurWeb.Storybook.Navigation.TabStrip do
  @moduledoc """
  The generic tab strip joining sibling pages under one sidebar entry.
  Tabs are page links with an optional pending count; the active tab is
  the page rendering the strip. Review and Discovery both render this.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.TabStrip.Tab

  def function, do: &MediaCentaurWeb.Components.TabStrip.tab_strip/1
  def render_source, do: :function

  defp tabs do
    [
      %Tab{id: :feed, label: "Feed", navigate: "#", count: 2},
      %Tab{id: :watchlist, label: "Watchlist", navigate: "#", count: 7},
      %Tab{id: :social, label: "Social", navigate: "#"}
    ]
  end

  def variations do
    [
      %Variation{
        id: :three_tabs,
        description:
          "Three sibling pages; counts badge the tabs with work, the active one is underlined.",
        attributes: %{tabs: tabs(), active: :watchlist, size: :md}
      },
      %Variation{
        id: :couch,
        description:
          "The couch size (`:lg`): 22px tabs with 18px counts, the underline at 3px — the Feed's strip, read from the sofa (UIDR-046).",
        attributes: %{tabs: tabs(), active: :feed, size: :lg}
      },
      %Variation{
        id: :single_tab,
        description: "One tab — the strip still renders as the section header the next tabs join.",
        attributes: %{tabs: Enum.take(tabs(), 1), active: :feed}
      },
      %Variation{
        id: :no_counts,
        description: "All counts at zero — no badges.",
        attributes: %{tabs: Enum.map(tabs(), &%{&1 | count: 0}), active: :friends}
      }
    ]
  end
end
