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
      %Tab{id: :friends, label: "Friends", navigate: "#"}
    ]
  end

  def variations do
    [
      %Variation{
        id: :three_tabs,
        description:
          "Three sibling pages; counts badge the tabs with work, the active one is underlined.",
        attributes: %{tabs: tabs(), active: :watchlist}
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
