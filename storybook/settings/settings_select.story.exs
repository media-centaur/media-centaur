defmodule MediaCentaurWeb.Storybook.Settings.SettingsSelect do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_select/1
  def render_source, do: :function

  @follow [
    {"added", "Only people I add"},
    {"members", "Everyone on this relay"}
  ]

  def variations do
    [
      %Variation{
        id: :follow_rule,
        description: "The bare select, as a field of a submit form: a relay's follow rule.",
        attributes: %{
          name: "follow",
          options: @follow,
          selected: "added",
          aria_label: "Who to follow"
        }
      },
      %Variation{
        id: :second_selected,
        description: "The second option chosen.",
        attributes: %{
          name: "follow",
          options: @follow,
          selected: "members",
          aria_label: "Who to follow"
        }
      }
    ]
  end
end
