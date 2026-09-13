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
      }
    ]
  end
end
