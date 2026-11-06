defmodule MediaCentaurWeb.Storybook.Composites.SeeAllTile do
  @moduledoc """
  The See all tile — the last slot of a shelf that has a page of its own, in
  the shape of the cards beside it. `:fill` takes whatever slot it is given:
  a marquee column, alone or sharing it.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.SeeAllTile

  def function, do: &SeeAllTile.see_all_tile/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :poster,
        description: "Beside 2:3 posters (Recently Added)",
        attributes: %{navigate: "/library", shape: :poster},
        template: ~s|<div class="w-[150px]"><.psb-variation/></div>|
      },
      %Variation{
        id: :backdrop,
        description: "Beside 16:9 backdrops (Continue Watching)",
        attributes: %{navigate: "/library?sort=watched", shape: :backdrop},
        template: ~s|<div class="w-[400px]"><.psb-variation/></div>|
      },
      %Variation{
        id: :fill_alone,
        description: "Alone in a marquee column",
        attributes: %{navigate: "/watchlist", shape: :fill, class: "flex-1"},
        template: ~s|<div class="w-[600px] h-[360px] flex flex-col"><.psb-variation/></div>|
      },
      %Variation{
        id: :fill_third,
        description: "A third of a marquee column (two tiles above it)",
        attributes: %{navigate: "/watchlist", shape: :fill, class: "flex-1"},
        template: ~s|<div class="w-[600px] h-[113px] flex flex-col"><.psb-variation/></div>|
      }
    ]
  end
end
