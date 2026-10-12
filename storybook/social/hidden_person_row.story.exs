defmodule MediaCentaurWeb.Storybook.Social.HiddenPersonRow do
  @moduledoc """
  One hidden person in the Friends tab's hidden group: the identity tile
  at 40, the name the reader sees, and Show. No acts: hidden means
  unseen. The rows sit in a list at the Friends page's width.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Social.Person

  def function, do: &MediaCentaurWeb.Components.Social.HiddenPersonRow.hidden_person_row/1
  def render_source, do: :function

  @list ~s(<ul class="w-[480px]"><.psb-variation/></ul>)

  defp hidden(overrides \\ %{}) do
    Map.merge(
      %Person{
        pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
        name_override: "Sample Friend",
        short_npub: "npub1lyy9…8z4h",
        hidden: true,
        friend?: true,
        added_on: ~D[2026-08-30]
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :named,
        description: "A hidden friend: tile, name, Show",
        template: @list,
        attributes: %{id: "hidden-1", person: hidden()}
      },
      %Variation{
        id: :unnamed_member,
        description:
          "A hidden member followed through a relay, with no name: the person glyph and Unnamed",
        template: @list,
        attributes: %{
          id: "hidden-2",
          person:
            hidden(%{
              name_override: nil,
              friend?: false,
              added_on: nil,
              member_of: ["wss://group.example/"]
            })
        }
      }
    ]
  end
end
