defmodule MediaCentaurWeb.Components.Social.FeedRow do
  @moduledoc """
  One row on the Feed and on the person page (UIDR-046, UIDR-054): one
  author's action on one title, or one person's acts on one title, as
  the app draws a list row. The identity tile at 40 and the name when
  the row has an author — never on the person page, which is one
  person — the poster at 80×120 beside it, then the words: the verb
  (`Nick reviewed`, `watched S02E05 of`, `You want to watch`) with every
  glyph after it at its grade (the review's sentiment on the Feed; every
  act on the title on the person page; nothing when there is none),
  which title (name and year), the episode's name on a series, and the
  review's words in full — and the relative time at the row's right
  edge, all hung from the row's top line. The words are
  never clipped: the protocol caps a review at 500 characters, about
  seven lines here, and a review of two lines or fewer sits beside the
  120px poster, so only a long review makes its row taller. The
  poster is the row's one picture; a title without one shows the empty
  slot. An own row is the filled own tile and the second-person verb;
  nothing else marks it. The type is the app's: 16px words, an 18px
  title, 14px for the year and the time.

  The toolbar is a fixed 32px seat under the words, empty at rest and
  shown while the row is hovered or holds focus, so hover never changes
  the row's height. Left to right: the List slot (the bookmark verb,
  "Listed" filled, or "Tracking" as plain state), the Download slot (the
  verb, or plain state text — "Downloading" with a hairline, "In
  library"), and Ignore when the subject is a friend. State and verb are one
  control. An own row has no Ignore and no Delete: withdrawing is the
  modal's Delete, and the row opens the modal speaking for its action.

  Pure rendering of a `FeedEntry`; the row decides nothing. Its DOM
  contract — `feed-row-<activity id>`, `data-component="feed-row"`, the
  slot attributes, the `data-role`s, the control ids — is what the page's
  tests hold on to. The whole row bubbles `open_title` with the ref and
  the activity; the verbs bubble `feed_list`, `feed_download` and
  `ignore_title` with the activity id. A `div[role=button]` because a
  button may not contain controls. The row is a nav item of the page's
  `feed` tree and its verbs are `data-nav-sub-item`s: UP and DOWN walk
  the rows, SELECT opens the title, RIGHT steps along the verbs. Focus
  shows the toolbar the way hover does. The rows sit in a column with a
  hairline between them and no ground of their own; the catalog pins the
  hovered seat with `.feed-hover-pin`, since a story cannot hover.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.SocialLive.ActivityWords
  alias MediaCentaurWeb.TitleRef

  @verb_class "inline-flex h-8 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-md px-1.5 hover:bg-base-content/10 hover:text-base-content/90"
  @state_class "inline-flex h-8 items-center whitespace-nowrap px-1.5 text-base-content/65"

  attr :entry, FeedEntry, required: true

  def feed_row(assigns) do
    assigns = assign(assigns, verb_class: @verb_class, state_class: @state_class)

    ~H"""
    <div
      id={@entry.id}
      role="button"
      class="group feed-row flex cursor-pointer items-start gap-4 rounded-lg px-4 py-4 text-left hover:bg-base-content/5"
      data-component="feed-row"
      data-kind={@entry.kind}
      data-own={@entry.subject == :you}
      data-list-slot={@entry.slots.list}
      data-download-slot={slot_name(@entry.slots.download)}
      phx-click="open_title"
      phx-value-ref={TitleRef.param(@entry.ref)}
      phx-value-activity={@entry.activity_id}
      data-entity-id={TitleRef.param(@entry.ref)}
      data-nav-item
      tabindex="0"
    >
      <IdentityTile.identity_tile
        :if={@entry.author}
        {IdentityTile.person_attrs(@entry.author)}
        size={40}
      />

      <img
        :if={@entry.poster_url}
        src={row_poster_src(@entry.poster_url)}
        alt=""
        class="h-[120px] w-20 shrink-0 rounded-md object-cover shadow-[0_3px_12px_oklch(0%_0_0/0.45)]"
        data-role="poster"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@entry.poster_url}
        class="h-[120px] w-20 shrink-0 rounded-md bg-base-content/6 ring-1 ring-inset ring-base-content/10"
        data-role="poster-empty"
      >
      </div>

      <div class="min-w-0 flex-1">
        <p class="truncate text-base leading-6 text-base-content/80" data-role="who">
          <span :if={@entry.author} class="font-medium text-base-content/95">
            {Format.person_name(@entry.author)}
          </span>
          {ActivityWords.verb_phrase(@entry.kind, @entry.episode, @entry.subject)}
          <SocialGlyph.social_glyph
            :for={{flag, grade} <- @entry.glyphs}
            flag={flag}
            grade={grade}
            class="ml-1 size-4 align-middle"
          />
        </p>
        <p class="flex items-baseline gap-2 text-lg font-semibold leading-7" data-role="title">
          <span class="truncate">{@entry.title.name}</span>
          <span :if={@entry.title.year} class="shrink-0 text-sm font-normal text-base-content/60">
            {@entry.title.year}
          </span>
        </p>
        <p
          :if={@entry.episode && @entry.episode.name}
          class="mt-1 text-base leading-6 text-base-content/80"
          data-role="episode"
        >
          {@entry.episode.name}
        </p>
        <p
          :if={@entry.text}
          class="mt-1 max-w-[40rem] text-base leading-6 text-base-content/80"
          data-role="text"
        >
          {@entry.text}
        </p>

        <div
          class="-mx-1.5 mt-1 flex h-8 items-center gap-0.5 text-sm text-base-content/80 opacity-0 transition-opacity duration-[120ms] group-hover:opacity-100 group-focus-within:opacity-100"
          data-role="toolbar"
        >
          <button
            :if={@entry.slots.list == :list}
            id={"#{@entry.id}-list"}
            type="button"
            class={@verb_class}
            data-nav-sub-item
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark" class="size-4" /> List
          </button>
          <button
            :if={@entry.slots.list == :listed}
            id={"#{@entry.id}-list"}
            type="button"
            class={[@verb_class, "text-base-content/90"]}
            data-nav-sub-item
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark-solid" class="size-4" /> Listed
          </button>
          <span :if={@entry.slots.list == :following} class={@state_class}>Tracking</span>

          <button
            :if={@entry.slots.download == :download}
            id={"#{@entry.id}-download"}
            type="button"
            class={@verb_class}
            data-nav-sub-item
            phx-click="feed_download"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download
          </button>
          <span :if={match?({:state, _}, @entry.slots.download)} class={@state_class}>
            <span class={[
              "relative",
              @entry.slots.acquisition_state == :downloading &&
                "after:absolute after:inset-x-0 after:-bottom-[3px] after:h-[3px] after:rounded-sm after:bg-base-content/40"
            ]}>
              {elem(@entry.slots.download, 1)}
            </span>
          </span>

          <button
            :if={@entry.subject == :friend}
            id={"#{@entry.id}-ignore"}
            type="button"
            class={[@verb_class, "ml-2.5"]}
            data-nav-sub-item
            phx-click="ignore_title"
            phx-value-activity={@entry.activity_id}
          >
            Ignore
          </button>
        </div>
      </div>

      <span class="shrink-0 pt-0.5 text-sm tabular-nums text-base-content/60" data-role="time">
        {@entry.ago}
      </span>
    </div>
    """
  end

  @doc "The `src` a row's poster paints at 80×120 CSS px — the 240 derivative the rail's posters share, so one file serves both."
  @spec row_poster_src(String.t() | nil) :: String.t() | nil
  def row_poster_src(url), do: sized_image_url(url, 240)

  defp slot_name(:download), do: "download"
  defp slot_name({:state, word}), do: word
end
