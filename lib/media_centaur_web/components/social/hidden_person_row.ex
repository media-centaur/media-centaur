defmodule MediaCentaurWeb.Components.Social.HiddenPersonRow do
  @moduledoc """
  One hidden person in the Friends tab's hidden group: the identity tile
  at 40, the name the reader sees (`Format.person_name/1`), and **Show**,
  which pushes `set_hidden` with the key and `hide` `"false"`. Pure
  rendering of a `Social.Person`; the acts are not drawn, since hidden
  means unseen. Show is pre-marked `data-nav-item` for the Social page's
  hardening pass, which registers the hidden group's zone; until then it
  is reached by Tab and mouse.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.IdentityTile

  attr :id, :string, required: true
  attr :person, Person, required: true, doc: "the person as the reader sees them; `hidden` is true"

  def hidden_person_row(assigns) do
    ~H"""
    <li id={@id} class="flex items-center gap-3 px-1 py-1" data-component="hidden-person-row">
      <IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={40} />
      <span class="min-w-0 flex-1 truncate" data-role="name">{Format.person_name(@person)}</span>
      <.button
        variant="neutral"
        size="xs"
        phx-click="set_hidden"
        phx-value-pubkey={@person.pubkey}
        phx-value-hide="false"
        data-nav-item
        tabindex="0"
      >
        Show
      </.button>
    </li>
    """
  end
end
