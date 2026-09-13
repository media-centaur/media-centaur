defmodule MediaCentaurWeb.Storybook.Settings.SettingsSelectRow do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_select_row/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :languages,
        description: "An enum too wide for the pill: a native select, saving on change.",
        attributes: %{
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
      }
    ]
  end
end
