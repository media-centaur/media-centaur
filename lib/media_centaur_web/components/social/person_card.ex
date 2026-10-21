defmodule MediaCentaurWeb.Components.Social.PersonCard do
  @moduledoc """
  One person as their latest acts (UIDR-046, UIDR-047), on the Feed's
  rail and the Friends page from one function at two widths. The head
  is the identity tile and the name the reader sees (`Format.person_name/1`)
  — no clock: the card says what a person did, the Feed says when; under
  it the **acts strip**: one poster per title acted on, newest first,
  each under its **social glyphs** — a 36px strip on the card's ground with
  the glyphs for what the person did centred as a group in order
  (the opinion, the eye, the bookmark), one act in the middle, two as a
  pair, each drawn at its grade (`Title.Grade`): plain is a
  white line drawing, silver and gold the solid glyph in metal. A person with
  no acts is a tile and a name; the card says nothing about what a
  person withholds, and the You card is the reader's acts like anyone's,
  the filled own tile its only mark.

  The rail's card (`width: :rail`) is a row in the rail's list — no
  ground of its own, a hairline between cards — showing three acts. The
  page's card (`:page`) is a card in the Friends grid on the inset tone,
  showing five acts. At both widths the head is a link to the person's
  page (`patch`, UIDR-054), where every act is a row and the reader's
  view lives; a poster's press opens the title modal speaking for the
  newest act on it.

  Pure rendering of a `Social.Person` and their rows (`FeedEntry`, one
  per title, `SocialLive.People`): the head and every poster are nav
  items; a poster bubbles `open_title` with the title's ref and the
  activity.
  """

  use Phoenix.Component

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.SocialLive.ActivityWords
  alias MediaCentaurWeb.TitleRef

  @cap %{rail: 3, page: 5}

  attr :person, Person, required: true, doc: "the person as the reader sees them"

  attr :acts, :list,
    required: true,
    doc: "the person's rows (`FeedEntry`, one per title), newest first; `[]` for a quiet person"

  attr :width, :atom, required: true, values: [:rail, :page]

  attr :patch, :string,
    required: true,
    doc: "the person page's address (`PersonPage.path/1`); the head links to it"

  def person_card(assigns) do
    assigns =
      assign(assigns,
        id: dom_id(assigns.person),
        name: Format.person_name(assigns.person),
        shown: Enum.take(assigns.acts, @cap[assigns.width]),
        subject: ActivityWords.subject(assigns.person),
        page?: assigns.width == :page
      )

    ~H"""
    <section
      id={@id}
      class={["person-card", @page? && "person-card-page"]}
      data-component="person-card"
      data-width={@width}
      data-own={@person.own?}
    >
      <.link
        patch={@patch}
        class="flex items-center gap-3 rounded-md"
        data-role="head"
        data-nav-item
        tabindex="0"
      >
        <IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={tile_size(@width)} />
        <h2
          class={[
            "min-w-0 flex-1 truncate font-semibold",
            if(@page?, do: "text-xl leading-8", else: "text-lg leading-7")
          ]}
          data-role="name"
        >
          {@name}
        </h2>
      </.link>

      <div
        :if={@acts != []}
        class={["acts-strip", if(@page?, do: "mt-4", else: "mt-2 pl-13")]}
        data-role="acts"
      >
        <button
          :for={row <- @shown}
          id={"#{@id}-act-#{TitleRef.param(row.ref)}"}
          type="button"
          class="act"
          data-tip={tip(@name, row, @subject)}
          aria-label={tip(@name, row, @subject)}
          phx-click="open_title"
          phx-value-ref={TitleRef.param(row.ref)}
          phx-value-activity={row.activity_id}
          data-entity-id={TitleRef.param(row.ref)}
          data-flags={Enum.map_join(row.glyphs, " ", &elem(&1, 0))}
          data-nav-item
          tabindex="0"
        >
          <SocialGlyph.social_glyphs
            flags={flags(row)}
            grades={Map.new(row.glyphs)}
            class="act-slots"
            aria-hidden="true"
          />
          <img
            :if={row.poster_url}
            src={act_poster_src(row.poster_url, @width)}
            alt={row.title.name}
            loading="eager"
            decoding="sync"
          />
          <span :if={!row.poster_url} class="act-empty text-sm leading-tight text-base-content/65">
            {row.title.name}
          </span>
        </button>
      </div>
    </section>
    """
  end

  @doc """
  The card's DOM id: `person-you` for the reader, else `person-` and the
  key's first eight hex digits; the hidden group's rows derive theirs
  from it.
  """
  @spec dom_id(Person.t()) :: String.t()
  def dom_id(%Person{own?: true}), do: "person-you"
  def dom_id(%Person{pubkey: pubkey}), do: "person-" <> String.slice(pubkey, 0, 8)

  @doc "The poster derivative for the width it paints at: 96 CSS px on the rail, 130 on the page, ×2 for a 4K panel."
  @spec act_poster_src(String.t(), :rail | :page) :: String.t()
  def act_poster_src(url, :rail), do: sized_image_url(url, 240)
  def act_poster_src(url, :page), do: sized_image_url(url, 320)

  defp tile_size(:rail), do: 40
  defp tile_size(:page), do: 48

  defp flags(%FeedEntry{glyphs: glyphs}), do: Enum.map(glyphs, &elem(&1, 0))

  defp tip(name, act, subject), do: name <> " " <> sentence(act, subject)

  defp sentence(%FeedEntry{} = row, subject),
    do: ActivityWords.sentence(row.kind, row.episode, row.title.name, subject)
end
