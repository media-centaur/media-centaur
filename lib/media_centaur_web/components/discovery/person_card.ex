defmodule MediaCentaurWeb.Components.Discovery.PersonCard do
  @moduledoc """
  One person as their latest acts (UIDR-046, UIDR-047), on the Feed's
  rail and the Friends page from one function at two widths. The head
  is the identity tile and the name the reader sees (`Format.person_name/1`)
  — no clock: the card says what a person did, the Feed says when; under
  it the **acts strip**: one poster per title acted on, newest first,
  each under its **act glyphs** — a 36px strip on the card's ground with
  the glyphs for what the person did centred as a group in mast order
  (the opinion, the eye, the bookmark), one act in the middle, two as a
  pair. A flag at the grade is gold; the rest are matte. A person with
  no acts is a tile and a name; the card says nothing about what a
  person withholds, and the You card is the reader's acts like anyone's,
  the filled own tile its only mark.

  The rail's card (`width: :rail`) is a row in the rail's list — no
  ground of its own, a hairline between cards — showing three acts; its
  press navigates to the person on the Friends page. The page's card
  (`:page`) is a card in the Friends grid on the inset tone, showing
  five acts. Its press opens the card in place (`opened?`, the host's
  set): every act, one row per poster in `ActivityWords`' sentence with
  the act's flags after the title, then a friend's foot. The foot is the
  reader's name for the friend, ready to change, over the name it masks
  as the field's placeholder (the published name, else Unnamed;
  UIDR-047); the **avatar switch**, *Show their picture*
  (`Components.Switch`), on while the reader shows the friend's
  published picture in every identity tile (`Person.show_avatar`) and
  off when the letter stands in for it; the key, the added date and
  Remove friend. A poster's press opens the title modal speaking for the
  newest act on it.

  Pure rendering of a `Social.Person` and their `Act`s. Every poster, row
  and Remove friend is a nav item that bubbles `open_title` with the
  title's ref *and* the activity, or `remove_friend`; the name form
  submits `set_friend_name` with the key and the name, and swallows its
  clicks (`phx-click={%JS{}}`, the modal panel's idiom) so typing in it
  does not press the card; the avatar switch pushes `set_show_avatar`
  with the key and the value to set — the opposite of the current — and
  its own `phx-click` is what keeps the card's press from it;
  `open_person` and `toggle_person` are the card's own presses. The root
  gets no nav wiring until the hardening pass.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.IdentityTile
  alias MediaCentaurWeb.Components.Switch
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef
  alias Phoenix.LiveView.JS

  @cap %{rail: 3, page: 5}

  attr :person, Person, required: true, doc: "the person as the reader sees them"
  attr :acts, :list, required: true, doc: "the person's `Act`s, newest first; `[]` for a quiet person"
  attr :width, :atom, required: true, values: [:rail, :page]
  attr :opened?, :boolean, default: false, doc: "the page card grown in place; the host keeps the set"
  attr :landed?, :boolean, default: false, doc: "the card the address names takes focus on mount"

  def person_card(assigns) do
    assigns =
      assign(assigns,
        id: dom_id(assigns.person),
        name: Format.person_name(assigns.person),
        shown: shown(assigns.acts, assigns.width, assigns.opened?),
        subject: ActivityWords.subject(assigns.person),
        page?: assigns.width == :page
      )

    ~H"""
    <section
      id={@id}
      role="button"
      tabindex="-1"
      class={["person-card", @page? && "person-card-page", @opened? && "person-card-opened"]}
      data-component="person-card"
      data-width={@width}
      data-own={@person.own?}
      data-opened={@opened?}
      phx-click={if @page?, do: "toggle_person", else: "open_person"}
      phx-value-id={@id}
      phx-mounted={@landed? && JS.focus()}
    >
      <header class="flex items-center gap-3">
        <IdentityTile.identity_tile person={@person} size={tile_size(@width)} />
        <h2
          class={[
            "min-w-0 flex-1 truncate font-semibold",
            if(@page?, do: "text-xl leading-8", else: "text-lg leading-7")
          ]}
          data-role="name"
        >
          {@name}
        </h2>
      </header>

      <div
        :if={@acts != []}
        class={["acts-strip", if(@page?, do: "mt-4", else: "mt-2 pl-13")]}
        data-role="acts"
      >
        <button
          :for={act <- @shown}
          id={"#{@id}-act-#{TitleRef.param(act.ref)}"}
          type="button"
          class="act"
          title={@name <> " " <> sentence(act, @subject)}
          phx-click="open_title"
          phx-value-ref={TitleRef.param(act.ref)}
          phx-value-activity={act.activity_id}
          data-entity-id={TitleRef.param(act.ref)}
          data-flags={Enum.join(act.flags, " ")}
          data-nav-item
          tabindex="0"
        >
          <span class="act-slots" aria-hidden="true">
            <span
              :for={flag <- act.flags}
              class={["act-glyph", flag in act.gold && "act-glyph-gold"]}
              data-flag={flag}
            >
              <.icon name={Flag.glyph(flag, :solid)} class="act-icon" />
            </span>
          </span>
          <img
            :if={act.poster_url}
            src={act_poster_src(act.poster_url, @width)}
            alt={act.title.name}
            loading="eager"
            decoding="sync"
          />
          <span :if={!act.poster_url} class="act-empty text-sm leading-tight text-base-content/65">
            {act.title.name}
          </span>
        </button>
      </div>

      <div :if={@opened?} class="mt-5 space-y-1" data-role="act-rows">
        <button
          :for={act <- @acts}
          id={"#{@id}-#{act.activity_id}"}
          type="button"
          class="flex w-full cursor-pointer items-baseline gap-3 rounded-md px-2 py-1 text-left text-base leading-6 hover:bg-base-content/5"
          data-role="act-row"
          phx-click="open_title"
          phx-value-ref={TitleRef.param(act.ref)}
          phx-value-activity={act.activity_id}
          data-entity-id={TitleRef.param(act.ref)}
          data-nav-item
          tabindex="0"
        >
          <span class="min-w-0 flex-1 truncate text-base-content/80">
            {ActivityWords.verb_phrase(newest(act).kind, act.episode, @subject)}
            <span class="font-medium text-base-content/95">{act.title.name}</span>
            <span :for={flag <- act.flags} class="ml-1 inline-block align-middle" data-flag={flag}>
              <.icon name={Flag.glyph(flag, :solid)} class="size-4 text-base-content/80" />
            </span>
          </span>
          <span class="shrink-0 text-sm text-base-content/65">{act.ago}</span>
        </button>
      </div>

      <footer
        :if={@opened? and not @person.own?}
        class="mt-5 space-y-3 border-t border-base-content/10 pt-4"
      >
        <form
          id={"#{@id}-name-form"}
          class="flex items-center gap-2"
          phx-submit="set_friend_name"
          phx-click={%JS{}}
          data-role="name-form"
        >
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <input
            type="text"
            name="name"
            value={@person.name_override}
            placeholder={masked_name(@person)}
            class="library-filter basis-48 grow-0 shrink-0"
            autocomplete="off"
            aria-label="Your name for this friend"
          />
          <.button type="submit" variant="neutral" size="sm">Rename</.button>
        </form>
        <Switch.switch
          id={"#{@id}-avatar-switch"}
          label="Show their picture"
          checked={@person.show_avatar}
          event="set_show_avatar"
          values={%{"pubkey" => @person.pubkey, "show" => to_string(not @person.show_avatar)}}
          class="-mx-2 px-2 py-1.5"
          data-role="avatar-switch"
        />
        <div class="flex items-center justify-between">
          <span class="text-sm text-base-content/65">
            <code>{@person.short_npub}</code> · added {Calendar.strftime(@person.added_on, "%b %-d")}
          </span>
          <.button
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
      </footer>
    </section>
    """
  end

  @doc """
  The card's DOM id: `person-you` for the reader, else `person-` and the
  key's first eight hex digits. The host's opened set and the address's
  `person=` speak it.
  """
  @spec dom_id(Person.t()) :: String.t()
  def dom_id(%Person{own?: true}), do: "person-you"
  def dom_id(%Person{pubkey: pubkey}), do: "person-" <> String.slice(pubkey, 0, 8)

  @doc "The poster derivative for the width it paints at: 96 CSS px on the rail, 130 on the page, ×2 for a 4K panel."
  @spec act_poster_src(String.t(), :rail | :page) :: String.t()
  def act_poster_src(url, :rail), do: sized_image_url(url, 240)
  def act_poster_src(url, :page), do: sized_image_url(url, 320)

  defp shown(acts, _width, true), do: acts
  defp shown(acts, width, false), do: Enum.take(acts, @cap[width])

  defp tile_size(:rail), do: 40
  defp tile_size(:page), do: 48

  # The name the override masks — the published one, else Unnamed — as
  # the foot's placeholder; never a literal here.
  defp masked_name(%Person{} = person), do: Format.person_name(%{person | name_override: nil})

  defp newest(%Act{entries: [entry | _rest]}), do: entry

  defp sentence(%Act{} = act, subject),
    do: ActivityWords.sentence(newest(act).kind, act.episode, act.title.name, subject)
end
