defmodule MediaCentaurWeb.Storybook.CoreComponents.SegmentedControl do
  @moduledoc """
  The house pick-one pill for content surfaces: a glass rail, the chosen
  option lifted, `aria-pressed` on it. The Feed's scope, Library's type
  tabs and the strip chart's window are this component; the Settings
  kit's choice row composes it.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.segmented_control/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :three_options,
        description: "Three options, the first chosen.",
        attributes: %{
          label: "Scope",
          options: [{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}],
          selected: :everyone,
          event: "pick"
        }
      },
      %Variation{
        id: :last_chosen,
        description: "The chosen option can be any of them.",
        attributes: %{
          label: "Scope",
          options: [{:everyone, "Everyone"}, {:friends, "Friends"}, {:you, "You"}],
          selected: :you,
          event: "pick"
        }
      },
      %Variation{
        id: :six_options,
        description: "A wider row: the strip chart's windows.",
        attributes: %{
          label: "Window",
          options: [{"5m", "5m"}, {"1h", "1h"}, {"5h", "5h"}, {"1d", "1d"}, {"1w", "1w"}, {"1mo", "1mo"}],
          selected: "1h",
          event: "pick"
        }
      }
    ]
  end
end
