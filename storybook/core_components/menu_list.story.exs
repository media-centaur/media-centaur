defmodule MediaCentaurWeb.Storybook.CoreComponents.MenuList do
  @moduledoc """
  The glass menu's list on its own (spec 2026-09-12 §13): items are nav
  items in the list's zone, the list carries the dismiss event BACK
  pushes, and the active item wears the primary colour. The tenants
  (`split_button`, `menu_select`) anchor it under their triggers; here it
  sits in a relative box so it renders in place.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.menu_list/1
  def render_source, do: :function

  # The list is `position: absolute` under its `.glass-menu` anchor. An
  # empty inline anchor has no height, so the list lands at the top of the
  # padded box instead of below it.
  def template do
    """
    <div class="pb-40">
      <span class="glass-menu inline-block">
        <.psb-variation/>
      </span>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :two_items,
        description: "Two choices, the first active.",
        attributes: %{id: "list-two", zone: "sample_menu", on_close: "close_menu"},
        slots: [
          ~s|<:item id="list-two-a" event="pick" values={%{"choice" => "a"}} active>Season 1</:item>|,
          ~s|<:item id="list-two-b" event="pick" values={%{"choice" => "b"}}>All seasons</:item>|
        ]
      },
      %Variation{
        id: :content_width,
        description: "`--content` sizing: the list hugs its longest label instead of its anchor.",
        attributes: %{
          id: "list-content",
          zone: "sample_menu",
          on_close: "close_menu",
          class: "glass-menu-list--content"
        },
        slots: [
          ~s|<:item id="list-content-a" event="pick">Manually select release</:item>|
        ]
      }
    ]
  end
end
