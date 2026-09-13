defmodule MediaCentaurWeb.Storybook.Settings.SettingsCard do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_card/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :plain,
        description: "Title and body.",
        attributes: %{title: "Search"},
        slots: [~s|<p class="text-sm">body</p>|]
      },
      %Variation{
        id: :with_description_and_action,
        description: "A one-line description under the title and an action on the title line.",
        attributes: %{
          title: "Download clients",
          description:
            "One client per protocol. Prowlarr sends each grab to the client that matches the indexer."
        },
        slots: [
          ~s|<:action><button class="btn btn-ghost btn-xs">Detect from Prowlarr</button></:action>|,
          ~s|<p class="text-sm">rows</p>|
        ]
      }
    ]
  end
end
