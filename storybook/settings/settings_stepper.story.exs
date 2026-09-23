defmodule MediaCentaurWeb.Storybook.Settings.SettingsStepper do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_stepper/1
  def render_source, do: :function

  @row %{
    label: "Season packs",
    description: "Take a pack only when you want at least this share of its episodes.",
    event: "set_auto_grab",
    event_value: %{"key" => "pack_min_fit"},
    reset_value: 75
  }

  # A card body about 19rem wide: what a half-width window leaves at 2×
  # UI scale. Whatever does not fit beside the text block drops beneath it.
  @narrow ~s|<div class="w-[21rem] glass-surface rounded-xl p-5"><.psb-variation/></div>|

  def variations do
    [
      %Variation{
        id: :mid,
        description: "Between the bounds, at the default: only Reset is inert.",
        attributes:
          Map.merge(@row, %{
            value_label: "75%",
            down_value: 70,
            up_value: 80,
            at_min: false,
            at_max: false,
            at_default: true
          })
      },
      %Variation{
        id: :at_min,
        description: "At the lower bound: Decrease is inert but stays focusable.",
        attributes:
          Map.merge(@row, %{
            value_label: "5%",
            down_value: 5,
            up_value: 10,
            at_min: true,
            at_max: false,
            at_default: false
          })
      },
      %Variation{
        id: :at_max,
        description: "At the upper bound: Increase is inert.",
        attributes:
          Map.merge(@row, %{
            value_label: "100%",
            down_value: 95,
            up_value: 100,
            at_min: false,
            at_max: true,
            at_default: false
          })
      },
      %Variation{
        id: :narrow,
        description: "A narrow card: the controls drop beneath the label, left-aligned.",
        template: @narrow,
        attributes:
          Map.merge(@row, %{
            value_label: "75%",
            down_value: 70,
            up_value: 80,
            at_min: false,
            at_max: false,
            at_default: true
          })
      }
    ]
  end
end
