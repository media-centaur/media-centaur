defmodule MediaCentaurWeb.Storybook.Social.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047, UIDR-053) from
  three facts — the name, the picture, the hue — and whether the person
  is of this install (filled) or a friend (tinted). The marks: the
  picture, else the first letter of the name, else the person glyph for
  a friend with no name at all. Five sizes: 32 in the title detail's
  social panel and lead review and the sidebar's profile switcher, 40 on
  a Feed row and the rail's person card, 48 on the Friends page's card
  and the Settings cards, 128 on the "Who's watching?" picker. The last
  group is the palette (UIDR-048).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Hue

  def function, do: &MediaCentaurWeb.Components.Social.IdentityTile.identity_tile/1
  def render_source, do: :function

  @photo "/images/storybook/sample-poster.jpg"

  def variations do
    [
      %VariationGroup{
        id: :panel_32,
        description: "32px: the social panel, the lead review and the sidebar switcher",
        variations: states(32)
      },
      %VariationGroup{
        id: :row_40,
        description: "40px: a Feed row and the rail card",
        variations: states(40)
      },
      %VariationGroup{
        id: :card_48,
        description: "48px: the Friends page's card and the Settings cards",
        variations: states(48)
      },
      %VariationGroup{
        id: :picker_128,
        description:
          "128px: a profile on the picker — always filled, never the glyph (a profile's name is required)",
        variations: [
          %Variation{id: :letter, attributes: %{name: "Ana", hue: 150, own?: true, size: 128}},
          %Variation{
            id: :picture,
            attributes: %{name: "Ana", picture_url: @photo, hue: 150, own?: true, size: 128}
          }
        ]
      },
      %VariationGroup{
        id: :hues,
        description:
          "The palette (UIDR-048): a friend's letter at every hue, then a filled tile at every hue, then a picture ringed in the hue; the first tile has no hue and is the default Blue",
        variations:
          [%Variation{id: :none, attributes: %{name: "Cleo", size: 48}}] ++
            for {name, hue} <- Hue.palette() do
              %Variation{
                id: String.to_atom("friend_" <> String.downcase(name)),
                description: "#{name} #{hue}",
                attributes: %{name: "Cleo", hue: hue, size: 48}
              }
            end ++
            for {name, hue} <- Hue.palette() do
              %Variation{
                id: String.to_atom("own_" <> String.downcase(name)),
                attributes: %{name: "You", hue: hue, own?: true, size: 48}
              }
            end ++
            [
              %Variation{
                id: :picture_teal,
                attributes: %{name: "Ada", picture_url: @photo, hue: 195, size: 48}
              },
              %Variation{
                id: :own_picture_violet,
                attributes: %{name: "You", picture_url: @photo, hue: 290, own?: true, size: 48}
              }
            ]
      }
    ]
  end

  defp states(size) do
    [
      %Variation{
        id: :letter,
        description: "A friend: the first letter of the name, in the default Blue on its tint",
        attributes: %{name: "Cleo", size: size}
      },
      %Variation{
        id: :glyph,
        description: "A friend with no name at all: the person glyph, never a letter",
        attributes: %{size: size}
      },
      %Variation{
        id: :picture,
        description: "A friend with a picture: inside a 1px ring in the hue",
        attributes: %{name: "Ada", picture_url: @photo, size: size}
      },
      %Variation{
        id: :own,
        description: "A person of this install: filled in the hue, the letter near-white",
        attributes: %{name: "You", own?: true, size: size}
      },
      %Variation{
        id: :own_picture,
        description: "A person of this install with a picture: a 2px ring",
        attributes: %{name: "You", picture_url: @photo, own?: true, size: size}
      }
    ]
  end
end
