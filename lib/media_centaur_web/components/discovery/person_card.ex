defmodule MediaCentaurWeb.Components.Discovery.PersonCard do
  @moduledoc """
  One person as their latest acts (UIDR-046), on the Feed's rail and
  the Friends page from one function at two widths. The head is the
  identity tile and the name — no clock: the card says what a person
  did, the Feed says when; under it the **acts strip**: one poster per
  title acted on, newest first, each under its **act glyphs** — a 36px
  strip on the card's ground with the glyphs for what the person did
  centred as a group in mast order (the opinion, the eye, the
  bookmark), one act in the middle, two as a pair. A flag at the grade
  is gold; the rest are matte. A person
  with no acts is a tile and a name; the card says nothing about what a
  person withholds, and the You card is the reader's acts like anyone's,
  the filled own tile its only mark.

  The rail's card (`width: :rail`) is a row in the rail's list — no
  ground of its own, a hairline between cards — showing three acts; its
  press navigates to the person on the Friends page. The page's card
  (`:page`) is a card in the Friends grid on the inset tone, showing
  five acts; its press opens the card in place
  (`opened?`, the host's set): every act, one row per poster in
  `ActivityWords`' sentence with the act's flags after the title, then
  a friend's foot — the key, the added date, Remove friend. A poster's
  press opens the title modal speaking for the newest act on it.

  Pure rendering of a `Person`. Every poster, row and Remove friend is a
  nav item that bubbles `open_title` with the title's ref *and* the
  activity, or `remove_friend`; `open_person` and `toggle_person` are
  the card's own presses. The root gets no nav wiring until the
  hardening pass.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias Phoenix.LiveView.JS
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaurWeb.Components.Discovery.IdentityTile
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.Components.Discovery.Person.Act
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef

  @cap %{rail: 3, page: 5}

  attr :person, Person, required: true
  attr :width, :atom, required: true, values: [:rail, :page]
  attr :opened?, :boolean, default: false, doc: "the page card grown in place; the host keeps the set"
  attr :landed?, :boolean, default: false, doc: "the card the address names takes focus on mount"

  def person_card(assigns) do
    assigns =
      assign(assigns,
        shown: shown(assigns.person.acts, assigns.width, assigns.opened?),
        subject: subject(assigns.person),
        page?: assigns.width == :page
      )

    ~H"""
    <section
      id={@person.id}
      role="button"
      tabindex="-1"
      class={["person-card", @page? && "person-card-page", @opened? && "person-card-opened"]}
      data-component="person-card"
      data-width={@width}
      data-own={@person.own?}
      data-opened={@opened?}
      phx-click={if @page?, do: "toggle_person", else: "open_person"}
      phx-value-id={@person.id}
      phx-mounted={@landed? && JS.focus()}
    >
      <header class="flex items-center gap-3">
        <IdentityTile.identity_tile name={@person.name} own?={@person.own?} size={tile_size(@width)} />
        <h2
          class={[
            "min-w-0 flex-1 truncate font-semibold",
            if(@page?, do: "text-xl leading-8", else: "text-lg leading-7")
          ]}
          data-role="name"
        >
          {@person.name}
        </h2>
      </header>

      <div
        :if={@person.acts != []}
        class={["acts-strip", if(@page?, do: "mt-4", else: "mt-2 pl-13")]}
        data-role="acts"
      >
        <button
          :for={act <- @shown}
          id={"#{@person.id}-act-#{TitleRef.param(act.ref)}"}
          type="button"
          class="act"
          title={@person.name <> " " <> sentence(act, @subject)}
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
          :for={act <- @person.acts}
          id={"#{@person.id}-#{act.activity_id}"}
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
        class="mt-5 flex items-center justify-between border-t border-base-content/10 pt-4"
      >
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
      </footer>
    </section>
    """
  end

  @doc "The poster derivative for the width it paints at: 96 CSS px on the rail, 130 on the page, ×2 for a 4K panel."
  @spec act_poster_src(String.t(), :rail | :page) :: String.t()
  def act_poster_src(url, :rail), do: sized_image_url(url, 240)
  def act_poster_src(url, :page), do: sized_image_url(url, 320)

  defp shown(acts, _width, true), do: acts
  defp shown(acts, width, false), do: Enum.take(acts, @cap[width])

  defp tile_size(:rail), do: 40
  defp tile_size(:page), do: 48

  defp subject(%Person{own?: true}), do: :you
  defp subject(%Person{}), do: :friend

  defp newest(%Act{entries: [entry | _rest]}), do: entry

  defp sentence(%Act{} = act, subject),
    do: ActivityWords.sentence(newest(act).kind, act.episode, act.title.name, subject)
end
