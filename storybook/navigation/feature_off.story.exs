defmodule MediaCentaurWeb.Storybook.Navigation.FeatureOff do
  @moduledoc """
  The one drawing of a feature that is off (ADR-081): a gated page, a
  hidden Settings section reached by URL, or the pairing page shows it in
  place of its content. The headline is the fact, the body the feature's
  registry line, the action the way out.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Features

  def function, do: &MediaCentaurWeb.Components.FeatureOff.feature_off/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :gated_page,
        description: "A gated page on the host: the reader can turn the feature on here.",
        attributes: %{id: "feature-off-social", feature: Features.get(:social)}
      },
      %Variation{
        id: :no_action,
        description:
          "A device that is not the host (the pairing page): the flag is the host's, so the body says where and there is no action.",
        attributes: %{id: "feature-off-players", feature: Features.get(:players), action?: false},
        slots: [
          "Turn it on under Settings → Feature flags on the computer running Media Centaur, then pair this device."
        ]
      }
    ]
  end
end
