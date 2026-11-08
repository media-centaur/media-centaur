defmodule MediaCentaurWeb.Storybook.CoreComponents.MenuTrigger do
  @moduledoc """
  The glass menu's quiet trigger on its own: the current value and a
  chevron, ghost text that grows a faint background on hover and while
  open. `menu_select` draws its trigger with it; the Watchlist row's
  state line composes it in front of the caught-up panel.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.GlassMenu.menu_trigger/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Closed: the value and a chevron pointing down.",
        attributes: %{id: "trigger-closed", open: false, on_toggle: "toggle", label: "Sort"},
        slots: ["Recently Added"]
      },
      %Variation{
        id: :open,
        description: "Open: the background shows and the chevron turns.",
        attributes: %{id: "trigger-open", open: true, on_toggle: "toggle", label: "Sort"},
        slots: ["Recently Added"]
      },
      %Variation{
        id: :dialog,
        description:
          "Anchoring a panel of controls rather than a list (`haspopup=\"dialog\"`): the Watchlist row's state line, a `data-nav-sub-item` of its row.",
        attributes: %{
          id: "trigger-point",
          open: false,
          on_toggle: "caught_up_panel_open",
          label: "Caught up through",
          haspopup: "dialog",
          controls: "caught-up-panel",
          sub_item: true,
          class: "text-base-content/80"
        },
        slots: ["Caught up through S02E05"]
      }
    ]
  end
end
