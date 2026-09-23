defmodule MediaCentaurWeb.Storybook.Settings.SettingsCard do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_card/1
  def render_source, do: :function

  # A card body about 19rem wide: what a half-width window leaves at 2×
  # UI scale. Whatever does not fit beside the text block drops beneath it.
  @narrow ~s|<div class="w-[21rem]"><.psb-variation/></div>|

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
      },
      %Variation{
        id: :narrow,
        description:
          "A narrow card: the title keeps one line; the action drops beneath it, right-aligned.",
        template: @narrow,
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
