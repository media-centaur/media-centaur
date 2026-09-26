defmodule MediaCentaurWeb.Storybook.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046): the monogram, the
  reader's own filled tile, and a photo in each, at the two sizes the
  surfaces render — 40 on a Feed row and the rail's person card, 48 on
  the Friends page's. No protocol event carries a photo yet; the photo
  variations pin the space the design leaves for one.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Discovery.IdentityTile.identity_tile/1
  def render_source, do: :function

  @photo "/images/storybook/sample-poster.jpg"

  def variations do
    [
      %VariationGroup{
        id: :row_40,
        description: "A Feed row and the rail's person card: 40px, the initial at 16",
        variations: states(40)
      },
      %VariationGroup{
        id: :page_48,
        description: "The Friends page's card: 48px, the initial at 19",
        variations: states(48)
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
