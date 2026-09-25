defmodule MediaCentaurWeb.Storybook.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046): the monogram, the
  reader's own filled tile, and a photo in each, at the three sizes the
  surfaces render — 48 in the Feed's rail, 56 on a band, 64 on the
  Friends page. No protocol event carries a photo yet; the photo
  variations pin the space the design leaves for one.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Discovery.IdentityTile.identity_tile/1
  def render_source, do: :function

  @photo "/images/storybook/sample-poster.jpg"

  def variations do
    [
      %VariationGroup{
        id: :rail_48,
        description: "The rail's person card: 48px, the initial at 19",
        variations: states(48)
      },
      %VariationGroup{
        id: :band_56,
        description: "A Feed band: 56px, the initial at 22",
        variations: states(56)
      },
      %VariationGroup{
        id: :page_64,
        description: "The Friends page's card: 64px, the initial at 26",
        variations: states(64)
      }
    ]
  end

  defp states(size) do
    [
      %Variation{
        id: :monogram,
        description: "A friend: the name's first letter on a primary tint",
        attributes: %{name: "Cleo", size: size}
      },
      %Variation{
        id: :photo,
        description: "A friend with a photo: the photo inside a neutral ring",
        attributes: %{name: "Ada", size: size, photo_url: @photo}
      },
      %Variation{
        id: :own,
        description: "The reader: filled with the button primary, the letter in white",
        attributes: %{name: "You", size: size, own?: true}
      },
      %Variation{
        id: :own_photo,
        description: "The reader with a photo: the photo inside a 2px primary ring",
        attributes: %{name: "You", size: size, own?: true, photo_url: @photo}
      }
    ]
  end
end
