defmodule MediaCentaurWeb.Storybook.Settings.SettingsField do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_field/1
  def render_source, do: :function

  # A card body about 19rem wide: what a half-width window leaves at 2×
  # UI scale. Whatever does not fit beside the text block drops beneath it.
  @narrow ~s|<div class="w-[21rem] glass-surface rounded-xl p-5"><.psb-variation/></div>|

  def variations do
    [
      %Variation{
        id: :inline,
        description: "Label and description on the left, a narrow control on the right.",
        attributes: %{
          label: "Address",
          description: "Must be reachable from this machine."
        },
        slots: [
          ~s|<input class="input input-bordered font-mono text-sm" value="http://localhost:9696" />|
        ]
      },
      %Variation{
        id: :stacked,
        description: "A wide control drops below the label.",
        attributes: %{
          label: "Address",
          description: "Must be reachable from this machine.",
          layout: :stacked
        },
        slots: [
          ~s|<input class="input input-bordered w-full font-mono text-sm" value="http://localhost:9696" />|
        ]
      },
      %Variation{
        id: :narrow_inline,
        description: "A narrow card: an inline control that no longer fits drops beneath the label.",
        template: @narrow,
        attributes: %{
          label: "Address",
          description: "Must be reachable from this machine."
        },
        slots: [
          ~s|<input class="input input-bordered font-mono text-sm" value="http://localhost:9696" />|
        ]
      }
    ]
  end
end
