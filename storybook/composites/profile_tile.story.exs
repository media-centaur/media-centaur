defmodule MediaCentaurWeb.Storybook.Composites.ProfileTile do
  @moduledoc """
  A profile on the "Who's watching?" picker (UIDR-053): the 128px filled
  identity tile over the name, which truncates to the tile's column.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ProfileTile.profile_tile/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :letter,
        description: "No picture: the first letter of the name, filled in the hue",
        attributes: %{name: "Ana", hue: 150}
      },
      %Variation{
        id: :picture,
        description: "A picture, ringed in the hue",
        attributes: %{name: "Ana", picture_url: "/images/storybook/sample-poster.jpg", hue: 150}
      },
      %Variation{
        id: :current,
        description: "The session's active profile, on a switch: the chosen outline a hue swatch wears",
        attributes: %{name: "Ana", hue: 150, current?: true}
      },
      %Variation{
        id: :long_name,
        description: "A long name truncates to the tile's column",
        attributes: %{name: "A Very Long Profile Name Indeed", hue: 45}
      }
    ]
  end
end
