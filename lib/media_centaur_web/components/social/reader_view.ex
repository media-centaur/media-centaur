defmodule MediaCentaurWeb.Components.Social.ReaderView do
  @moduledoc """
  The reader's view of one person (UIDR-054): the settings a reader keeps
  about a friend or a member and that nobody else sees, as one Settings
  card (`Components.Settings`, UIDR-041) headed *Your view of <name>*.
  Rows, in order: **Name** — the reader's name for them in a field with
  Rename, the name it masks (the published one, else Unnamed) as the
  placeholder (UIDR-047); the form submits `set_friend_name` with the
  key and the name, a blank clearing it. **Show their picture**, a
  switch pushing `set_show_avatar` with the key and the value to set.
  **Colour** (`HueSwatches`, UIDR-048): Theirs, the published hue, then
  the palette and the ring, pushing `set_hue_override` with the key and
  the hue, empty for Theirs; the slider through the row's own form.
  **Hide**, a switch pushing `set_hidden` with the key and the value to
  set — the hidden group's Show sends the same. The foot: the short npub
  and how the reader follows them — *added* and the date for a friend,
  *on* the relay's host for a member — and, for a friend only, **Remove
  friend** (`remove_friend` with the key). Pure rendering of a
  `Social.Person`; never drawn for the reader's own, whose name, picture
  and colour are under Settings → Social.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Settings
  alias MediaCentaurWeb.Components.Social.HueSwatches

  attr :id, :string, default: "reader-view"

  attr :person, Person,
    required: true,
    doc: "a friend or a member as the reader sees them; never the reader's own"

  def reader_view(assigns) do
    assigns = assign(assigns, name: Format.person_name(assigns.person))

    ~H"""
    <Settings.settings_card
      id={@id}
      title={"Your view of #{@name}"}
      description={"Only you see these. They change nothing for #{@name} or anyone else."}
      data-component="reader-view"
    >
      <Settings.settings_field
        label="Name"
        description="What you call them. Blank shows the name they publish."
        layout={:stacked}
      >
        <form
          id={"#{@id}-name-form"}
          class="flex items-center gap-2"
          phx-submit="set_friend_name"
          data-role="name-form"
        >
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <Settings.settings_input
            name="name"
            value={@person.name_override}
            placeholder={masked_name(@person)}
            class="max-w-64"
            autocomplete="off"
          />
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            Rename
          </.button>
        </form>
      </Settings.settings_field>

      <Settings.settings_row
        label="Show their picture"
        description="Their published picture in every tile; off shows the letter."
        checked={@person.show_avatar}
        event="set_show_avatar"
        event_value={%{"pubkey" => @person.pubkey, "show" => to_string(not @person.show_avatar)}}
      />

      <Settings.settings_field
        label="Colour"
        description="The hue their tile and marks are drawn in."
        layout={:stacked}
      >
        <form id={"#{@id}-hue-form"} phx-change="set_hue_override" data-role="hue-form">
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <HueSwatches.hue_swatches
            id={"#{@id}-hues"}
            selected={@person.hue_override}
            theirs?
            theirs_hue={@person.published_hue}
            event="set_hue_override"
            values={%{"pubkey" => @person.pubkey}}
            aria-label="Colour"
          />
        </form>
      </Settings.settings_field>

      <Settings.settings_row
        label="Hide"
        description="Keeps their activity off the Feed, titles and the Friends grid."
        checked={@person.hidden}
        event="set_hidden"
        event_value={%{"pubkey" => @person.pubkey, "hide" => to_string(not @person.hidden)}}
      />

      <div class="flex items-center justify-between gap-2 pt-1" data-role="foot">
        <span class="text-sm text-base-content/65">
          <code>{@person.short_npub}</code> · {provenance(@person)}
        </span>
        <.button
          :if={@person.friend?}
          variant="dismiss"
          size="sm"
          phx-click="remove_friend"
          phx-value-pubkey={@person.pubkey}
          data-nav-item
          tabindex="0"
        >
          Remove friend
        </.button>
      </div>
    </Settings.settings_card>
    """
  end

  # The name the override masks — the published one, else Unnamed — as
  # the field's placeholder; never a literal here.
  defp masked_name(%Person{} = person), do: Format.person_name(%{person | name_override: nil})

  # How the reader came to follow the person: the day they added them,
  # else the relay whose members they follow.
  defp provenance(%Person{friend?: true, added_on: %Date{} = added_on}),
    do: "added " <> Calendar.strftime(added_on, "%b %-d")

  defp provenance(%Person{} = person), do: "on " <> Enum.join(Person.member_hosts(person), ", ")
end
