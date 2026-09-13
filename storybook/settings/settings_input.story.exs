defmodule MediaCentaurWeb.Storybook.Settings.SettingsInput do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_input/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :text,
        description: "The house text input, monospace for an address.",
        attributes: %{name: "prowlarr_url", value: "http://localhost:9696", mono: true}
      },
      %Variation{
        id: :password,
        description: "A secret: the placeholder says what a blank submission means.",
        attributes: %{
          type: "password",
          name: "prowlarr_api_key",
          placeholder: "Leave blank to keep the current key",
          mono: true
        }
      }
    ]
  end
end
