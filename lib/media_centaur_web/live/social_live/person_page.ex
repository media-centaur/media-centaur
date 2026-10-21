defmodule MediaCentaurWeb.SocialLive.PersonPage do
  @moduledoc """
  The person page (UIDR-054): one page per known person, the reader
  included, at `/social/friends/<npub>` and `/social/friends/you`.

  The pure half: `path/1`, a person's address, and `find/2`, the person
  an address's key names among the known people (`Social.people/0`'s
  map, the hidden included) — `you` is the reader's own, else the key
  parsed as npub or hex; nil when nobody known holds it, which the page
  answers by returning to Friends.

  The drawn half, `person_page/1`: the back row, the head (the identity
  tile at 48 and the name), then the person's activity as the Feed's
  rows folded one per title — `People`'s acts, drawn by `FeedRow`
  without the identity tile — beside the reader's view (`ReaderView`)
  for a friend or a member. The reader's own page has no card, only the
  pointer to Settings → Social. A hidden person's rows are never loaded
  (hidden means off everything), so their page is the head and the card
  over the hidden empty state; a shown person with no acts reads
  *Nothing yet*. Two nav zones: `person_rows`, the back row and the rows
  as a tree; `person_view`, the card's controls.
  """

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: MediaCentaurWeb.Endpoint, router: MediaCentaurWeb.Router

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedRow
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Components.Social.ReaderView
  alias MediaCentaurWeb.SocialLive.People.Card

  @doc "The address of a person's page: `you` for the reader, else their npub."
  @spec path(Person.t()) :: String.t()
  def path(%Person{own?: true}), do: ~p"/social/friends/you"
  def path(%Person{pubkey: pubkey}), do: ~p"/social/friends/#{Social.to_npub(pubkey)}"

  @doc "The person `key` names among `people` (pubkey → person): the reader's own for `you`, else the key parsed as npub or hex; nil when nobody known holds it."
  @spec find(String.t(), %{optional(String.t()) => Person.t()}) :: Person.t() | nil
  def find("you", people), do: Enum.find_value(people, fn {_pubkey, person} -> person.own? && person end)

  def find(key, people) do
    case Social.parse_pubkey(key) do
      {:ok, pubkey} -> Map.get(people, pubkey)
      {:error, :invalid_pubkey} -> nil
    end
  end

  attr :person, Person, required: true, doc: "the person the address names"

  attr :card, Card,
    default: nil,
    doc: "their card from `People.build/3`; nil for a hidden person, whose rows are never loaded"

  def person_page(assigns) do
    assigns =
      assign(assigns,
        name: Format.person_name(assigns.person),
        acts: if(assigns.card, do: assigns.card.acts, else: [])
      )

    ~H"""
    <div
      id="person-page"
      class="person-page"
      data-component="person-page"
      data-own={@person.own?}
      data-hidden={@person.hidden}
    >
      <div class="min-w-0" data-nav-zone="person_rows">
        <.link
          id="person-page-back"
          patch={~p"/social/friends"}
          class="mb-4 inline-flex items-center gap-1.5 rounded-md px-1 text-sm text-base-content/60 hover:text-base-content"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-chevron-left" class="size-3.5" /> Friends
        </.link>

        <header class="flex items-center gap-3.5 px-1" data-role="head">
          <IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={48} />
          <h2 class="min-w-0 flex-1 truncate text-xl font-semibold leading-8" data-role="name">
            {@name}
          </h2>
        </header>

        <div :if={@acts != []} id="person-rows" class="mt-3 divide-y divide-base-content/10">
          <FeedRow.feed_row :for={act <- @acts} entry={act} />
        </div>
        <p
          :if={@acts == [] and not @person.hidden}
          id="person-rows-empty"
          class="mt-6 px-4 text-sm text-base-content/65"
        >
          Nothing yet.
        </p>
        <p
          :if={@person.hidden}
          id="person-rows-hidden"
          class="mt-6 max-w-[60ch] px-4 text-sm text-base-content/65"
        >
          Hidden. Their activity is kept off the Feed, titles and Friends. Switch Hide off to see it here.
        </p>
        <p
          :if={@person.own?}
          id="person-settings-pointer"
          class="mt-6 px-4 text-xs text-base-content/55"
        >
          Your name, picture and colour are under <.link
            navigate={~p"/settings?section=social"}
            class="link link-primary"
          >Settings → Social</.link>.
        </p>
      </div>

      <div :if={not @person.own?} class="person-page-side" data-nav-zone="person_view">
        <ReaderView.reader_view person={@person} />
      </div>
    </div>
    """
  end
end
