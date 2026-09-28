defmodule MediaCentaurWeb.Storybook.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047): the three
  marks — the avatar, the letter, the person glyph for a friend with no
  name at all — for a friend and for the reader's own filled tile, at
  the two sizes the surfaces render: 40 on a Feed row and the rail's
  person card, 48 on the Friends page's card and the Settings profile
  card. The avatar is the picture a key published with its profile.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Social.Hue
  alias MediaCentaur.Social.Person

  def function, do: &MediaCentaurWeb.Components.Discovery.IdentityTile.identity_tile/1
  def render_source, do: :function

  @friend "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @me "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
  @photo "/images/storybook/sample-poster.jpg"

  def variations do
    [
      %VariationGroup{
        id: :row_40,
        description: "A Feed row and the rail's person card: 40px, the letter at 16",
        variations: states(40)
      },
      %VariationGroup{
        id: :page_48,
        description: "The Friends page's card: 48px, the letter at 19",
        variations: states(48)
      },
      %VariationGroup{
        id: :hues,
        description:
          "The palette (UIDR-048): a friend's letter at every hue, then the reader's own, then a picture ringed in the hue; the first tile has no hue and is the default Blue",
        variations:
          [
            %Variation{id: :none, attributes: %{person: friend("Cleo"), size: 48}}
          ] ++
            for {name, hue} <- Hue.palette() do
              %Variation{
                id: String.to_atom("friend_" <> String.downcase(name)),
                description: "#{name} #{hue}",
                attributes: %{person: %{friend("Cleo") | published_hue: hue}, size: 48}
              }
            end ++
            for {name, hue} <- Hue.palette() do
              %Variation{
                id: String.to_atom("own_" <> String.downcase(name)),
                attributes: %{person: %Person{pubkey: @me, own?: true, published_hue: hue}, size: 48}
              }
            end ++
            [
              %Variation{
                id: :avatar_teal,
                description:
                  "A friend's picture ringed in Teal; the override wins over the published Rose",
                attributes: %{
                  person: %{friend("Ada") | avatar_url: @photo, published_hue: 12, hue_override: 195},
                  size: 48
                }
              },
              %Variation{
                id: :own_avatar_violet,
                attributes: %{
                  person: %Person{pubkey: @me, own?: true, avatar_url: @photo, published_hue: 290},
                  size: 48
                }
              }
            ]
      }
    ]
  end

  defp states(size) do
    [
      %Variation{
        id: :letter,
        description: "A friend: the first letter of your name for them on a primary tint",
        attributes: %{person: friend("Cleo"), size: size}
      },
      %Variation{
        id: :glyph,
        description:
          "A friend with no name at all: the person glyph on the primary tint, never a letter",
        attributes: %{person: friend(nil), size: size}
      },
      %Variation{
        id: :avatar,
        description: "A friend with an avatar: the picture inside a neutral ring",
        attributes: %{person: %{friend("Ada") | avatar_url: @photo}, size: size}
      },
      %Variation{
        id: :own,
        description: "The reader: filled with the button primary, the Y of You in white",
        attributes: %{person: %Person{pubkey: @me, own?: true}, size: size}
      },
      %Variation{
        id: :own_avatar,
        description: "The reader with an avatar: the picture inside a 2px primary ring",
        attributes: %{person: %Person{pubkey: @me, own?: true, avatar_url: @photo}, size: size}
      }
    ]
  end

  defp friend(name),
    do: %Person{
      pubkey: @friend,
      name_override: name,
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
end
