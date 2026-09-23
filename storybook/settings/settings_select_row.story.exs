defmodule MediaCentaurWeb.Storybook.Settings.SettingsSelectRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_select_row/1
  def render_source, do: :function

  # A card body about 19rem wide: what a half-width window leaves at 2×
  # UI scale. Whatever does not fit beside the text block drops beneath it.
  @narrow ~s|<div class="w-[21rem] glass-surface rounded-xl p-5"><.psb-variation/></div>|

  @audio %{
    label: "Preferred audio",
    description: "Which audio track plays first.",
    name: "audio",
    options: [
      {"original", "Original language"},
      {"understood", "A language you understand"},
      {"any", "Any"}
    ],
    selected: "original",
    event: "set_language_policy"
  }

  def variations do
    [
      %Variation{
        id: :languages,
        description: "An enum too wide for the pill: a native select, saving on change.",
        attributes: @audio
      },
      %Variation{
        id: :narrow,
        description: "A narrow card: the select drops beneath the label, left-aligned.",
        template: @narrow,
        attributes: @audio
      }
    ]
  end
end
