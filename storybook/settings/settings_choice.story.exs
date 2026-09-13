defmodule MediaCentaurWeb.Storybook.Settings.SettingsChoice do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_choice/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :two,
        description: "Two options on the house segmented pill; the chosen one is lifted.",
        attributes: %{
          label: "Highest resolution",
          description: "The best available is taken right away.",
          options: [{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}],
          selected: "uhd_4k",
          event: "set_auto_grab",
          event_value: %{"key" => "default_max_quality"}
        }
      },
      %Variation{
        id: :three,
        description: "Three options.",
        attributes: %{
          label: "When a release appears",
          description: "Ask first parks the plan on Incoming until you approve it.",
          options: [{"all_releases", "Grab it"}, {"ask", "Ask first"}, {"off", "Notify only"}],
          selected: "ask",
          event: "set_auto_grab",
          event_value: %{"key" => "default_mode"}
        }
      }
    ]
  end
end
