defmodule MediaCentaurWeb.Storybook.Social.ReaderView do
  @moduledoc """
  The reader's view of one person (UIDR-054): the Settings-kit card on
  the person page's right — Name with Rename over the name it masks,
  Show their picture, Colour with Theirs first, Hide — and the foot: the
  key, how the reader follows them, Remove friend for a friend. Never
  for the reader's own.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Social.Person

  def function, do: &MediaCentaurWeb.Components.Social.ReaderView.reader_view/1
  def render_source, do: :function
  def layout, do: :one_column
  def template, do: ~s(<div class="w-[440px]"><.psb-variation/></div>)

  defp friend do
    %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: "Sample Friend",
      own?: false,
      friend?: true,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
  end

  def variations do
    [
      %Variation{
        id: :friend,
        description:
          "A friend: the common state — nothing published yet, the picture switch on over the letter, Theirs the default hue, Hide off, Remove friend",
        attributes: %{id: "rv-friend", person: friend()}
      },
      %Variation{
        id: :published_name,
        description:
          "A friend who published a name: the override in the field, the published name as its placeholder",
        attributes: %{id: "rv-published", person: %{friend() | published_name: "Ada"}}
      },
      %Variation{
        id: :picture_off,
        description: "The picture switch off",
        attributes: %{id: "rv-picture-off", person: %{friend() | show_avatar: false}}
      },
      %Variation{
        id: :hue_override,
        description: "A friend who published Rose, overridden with Teal: Theirs in Rose, Teal pressed",
        attributes: %{id: "rv-hue", person: %{friend() | published_hue: 12, hue_override: 195}}
      },
      %Variation{
        id: :member,
        description:
          "A member followed through a relay set to Everyone on this relay: the foot names the relay, no Remove friend",
        attributes: %{
          id: "rv-member",
          person: %{
            friend()
            | friend?: false,
              added_on: nil,
              member_of: ["wss://group.example/"],
              name_override: nil,
              published_name: "Sample Member"
          }
        }
      },
      %Variation{
        id: :hidden,
        description: "A hidden person: Hide on",
        attributes: %{id: "rv-hidden", person: %{friend() | hidden: true}}
      }
    ]
  end
end
