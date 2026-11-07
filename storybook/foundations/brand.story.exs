defmodule MediaCentaurWeb.Storybook.Foundations.Brand do
  @moduledoc """
  The app's mark — the centaur over its name — for a surface that stands
  alone: the pairing page and the profile picker in a compact window.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Brand.brand/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "The lockup as the pairing page and the picker show it on a phone.",
        attributes: %{}
      }
    ]
  end
end
