defmodule MediaCentaurWeb.Storybook.Discovery.HueSwatches do
  @moduledoc """
  The one place a hue is chosen (UIDR-048): eight palette swatches on
  the ring, the chosen one pressed, and the ring as a slider under them.
  On Settings the row picks the reader's own hue; on a friend's card
  foot it leads with Theirs, the friend's published hue, pressed while
  the reader has not chosen another.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Discovery.HueSwatches.hue_swatches/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :settings,
        description: "Settings → Your profile: Teal chosen, the slider's thumb at 195",
        attributes: %{id: "hues-settings", selected: 195, event: "set_profile_hue"}
      },
      %Variation{
        id: :custom,
        description: "A hue off the palette from the slider: no swatch pressed, the thumb at 100",
        attributes: %{id: "hues-custom", selected: 100, event: "set_profile_hue"}
      },
      %Variation{
        id: :foot_theirs,
        description:
          "A friend's card foot: Theirs leads in the friend's Rose and is pressed; no override",
        attributes: %{
          id: "hues-theirs",
          selected: nil,
          theirs?: true,
          theirs_hue: 12,
          event: "set_hue_override"
        }
      },
      %Variation{
        id: :foot_overridden,
        description: "The reader chose Violet over the friend's Rose",
        attributes: %{
          id: "hues-over",
          selected: 290,
          theirs?: true,
          theirs_hue: 12,
          event: "set_hue_override"
        }
      },
      %Variation{
        id: :foot_no_published,
        description: "A friend who published no hue: Theirs is the default Blue",
        attributes: %{
          id: "hues-none",
          selected: nil,
          theirs?: true,
          theirs_hue: nil,
          event: "set_hue_override"
        }
      }
    ]
  end
end
