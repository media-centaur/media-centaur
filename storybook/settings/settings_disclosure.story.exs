defmodule MediaCentaurWeb.Storybook.Settings.SettingsDisclosure do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_disclosure/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :closed,
        description: "Rare content behind a caret and a label.",
        attributes: %{label: "Secret key"},
        slots: [~s|<p class="text-xs">hidden until opened</p>|]
      },
      %Variation{
        id: :open,
        description: "Opened: the body sits under a hairline, indented.",
        attributes: %{label: "Secret key", open: true},
        slots: [~s|<p class="text-xs">the body</p>|]
      }
    ]
  end
end
