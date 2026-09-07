defmodule MediaCentaurWeb.Storybook.CoreComponents.ArmedButton do
  @moduledoc """
  Story for `<.armed_button>` — the two-click destructive gesture
  (MC0027 tier 2). Idle it looks like its `variant`; armed it is
  house-owned: error-toned, led by a warning glyph, relabelled with what
  the second click does. `class` styles the idle control only.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.armed_button/1
  def render_source, do: :function

  def imports, do: [{MediaCentaurWeb.CoreComponents, icon: 1}]

  def variations do
    [
      %VariationGroup{
        id: :idle,
        description: "Before the first click, in each idle variant",
        variations:
          for {variant, id} <- [
                {"danger", :danger},
                {"risky", :risky},
                {"dismiss", :dismiss},
                {"destructive_inline", :destructive_inline}
              ] do
            %Variation{
              id: id,
              attributes: %{
                armed: false,
                arm: "noop",
                fire: "noop",
                armed_label: "Click again to delete",
                variant: variant
              },
              slots: ["Delete"]
            }
          end
      },
      %VariationGroup{
        id: :icon_only,
        description:
          "An icon-only trigger (row cancel / remove): the muted resting colour rides in `class` and applies to the idle control only — the armed label it grows into keeps the house look",
        variations: [
          %Variation{
            id: :idle,
            attributes: %{
              armed: false,
              arm: "noop",
              fire: "noop",
              armed_label: "Click again to remove",
              variant: "destructive_inline",
              size: "xs",
              class: "text-base-content/55 hover:text-error",
              "aria-label": "Remove"
            },
            slots: [~s|<.icon name="hero-x-mark-mini" class="size-4" />|]
          },
          %Variation{
            id: :armed,
            attributes: %{
              armed: true,
              arm: "noop",
              fire: "noop",
              armed_label: "Click again to remove",
              variant: "destructive_inline",
              size: "xs",
              class: "text-base-content/55 hover:text-error",
              "aria-label": "Remove"
            },
            slots: [~s|<.icon name="hero-x-mark-mini" class="size-4" />|]
          }
        ]
      },
      %VariationGroup{
        id: :armed,
        description: "After the first click — error-toned, warning glyph, relabelled, aria-pressed",
        variations:
          for {size, id} <- [{"xs", :armed_xs}, {"sm", :armed_sm}, {"md", :armed_md}, {"lg", :armed_lg}] do
            %Variation{
              id: id,
              attributes: %{
                armed: true,
                arm: "noop",
                fire: "noop",
                armed_label: "Click again to delete",
                size: size
              },
              slots: ["Delete"]
            }
          end
      }
    ]
  end
end
