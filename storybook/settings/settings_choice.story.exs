defmodule MediaCentaurWeb.Storybook.Settings.SettingsChoice do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_choice/1
  def render_source, do: :function

  # A card body about 19rem wide: what a half-width window leaves at 2×
  # UI scale. Whatever does not fit beside the text block drops beneath it.
  @narrow ~s|<div class="w-[21rem] glass-surface rounded-xl p-5"><.psb-variation/></div>|

  @resolution %{
    label: "Highest resolution",
    description: "The best available is taken right away.",
    options: [{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}],
    selected: "uhd_4k",
    event: "set_auto_grab",
    event_value: %{"key" => "default_max_quality"}
  }

  @planning_mode %{
    label: "Default action on a title you don't own yet",
    description:
      "The other choice stays in the button's menu. Also decides whether auto-grab asks first.",
    options: [{"manual", "Manually select release"}, {"auto", "Auto-select best release"}],
    selected: "auto",
    event: "set_planning_mode"
  }

  def variations do
    [
      %Variation{
        id: :two,
        description: "Two options on the house segmented pill; the chosen one is lifted.",
        attributes: @resolution
      },
      %Variation{
        id: :long_labels,
        description: "Two long labels: a wide pill beside a text block that keeps its measure.",
        attributes: @planning_mode
      },
      %Variation{
        id: :three,
        description: "Three options.",
        attributes: %{
          label: "Three-way example",
          description: "A pill with three choices; the chosen one is lifted.",
          options: [{"one", "One"}, {"two", "Two"}, {"three", "Three"}],
          selected: "two",
          event: "set_example",
          event_value: %{"key" => "example"}
        }
      },
      %Variation{
        id: :narrow_drop,
        description: "A narrow card: the pill drops beneath the label, left-aligned.",
        template: @narrow,
        attributes: @resolution
      },
      %Variation{
        id: :narrow_wrap,
        description:
          "A narrow card and a pill wider than it: the tabs wrap into a second row inside the rail.",
        template: @narrow,
        attributes: @planning_mode
      }
    ]
  end
end
