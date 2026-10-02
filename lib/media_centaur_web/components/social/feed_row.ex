defmodule MediaCentaurWeb.Components.Social.FeedRow do
  @moduledoc """
  One row on the Feed (UIDR-046): one author's action on one title, as
  the app draws a list row. The identity tile at 40, the poster at
  80×120 beside it, then the words — who did what (`Nick reviewed ♥`,
  `You want to watch`; the sentiment glyph after the verb when the
  review gives one, nothing when it gives none), which title (name and
  year), and the review's words at two lines at most — and the relative
  time at the row's right edge, all hung from the row's top line. The
  poster is the row's one picture; a title without one shows the empty
  slot. An own row is the filled own tile and the second-person verb;
  nothing else marks it. The type is the app's: 16px words, an 18px
  title, 14px for the year and the time.

  The toolbar is a fixed 32px seat under the words, empty at rest and
  shown while the row is hovered or holds focus, so hover never changes
  the row's height. Left to right: the List slot (the bookmark verb,
  "Listed" filled, or "Tracking" as plain state), the Download slot (the
  verb, or plain state text — "Downloading" with a hairline, "In
  library"), and Ignore on a friend's row only. State and verb are one
  control. An own row has no Ignore and no Delete: withdrawing is the
  modal's Delete, and the row opens the modal speaking for its action.

  Pure rendering of a `FeedEntry`; the row decides nothing. Its DOM
  contract — `feed-row-<activity id>`, `data-component="feed-row"`, the
  slot attributes, the `data-role`s, the control ids — is what the page's
  tests hold on to. The whole row bubbles `open_title` with the ref and
  the activity; the verbs bubble `feed_list`, `feed_download` and
  `ignore_title` with the activity id. A `div[role=button]` because a
  button may not contain controls. Ships mouse-only: no nav items until
  the hardening pass. The rows sit in a column with a hairline between
  them and no ground of their own; the catalog pins the hovered seat with
  `.feed-hover-pin`, since a story cannot hover.
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
      data-own={@entry.author.own?}
      data-list-slot={@entry.list_slot}
      data-download-slot={slot_name(@entry.download_slot)}
      phx-click="open_title"
      phx-value-ref={TitleRef.param(@entry.ref)}
      phx-value-activity={@entry.activity_id}
      data-entity-id={TitleRef.param(@entry.ref)}
    >
      <IdentityTile.identity_tile person={@entry.author} size={40} />

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
          <span class="font-medium text-base-content/95">{Format.person_name(@entry.author)}</span>
          {ActivityWords.verb(@entry.kind, nil, ActivityWords.subject(@entry.author))}
          <SocialGlyph.social_glyph
            :if={@entry.sentiment}
            flag={@entry.sentiment}
            class="size-4 align-middle"
          />
        </p>
        <p class="flex items-baseline gap-2 text-lg font-semibold leading-7" data-role="title">
          <span class="truncate">{@entry.title.name}</span>
          <span :if={@entry.title.year} class="shrink-0 text-sm font-normal text-base-content/60">
            {@entry.title.year}
          </span>
        </p>
        <p
          :if={@entry.text}
          class="mt-1 line-clamp-2 max-w-[40rem] text-base leading-6 text-base-content/80"
          data-role="text"
        >
          {@entry.text}
        </p>

        <div
          class="-mx-1.5 mt-1 flex h-8 items-center gap-0.5 text-sm text-base-content/80 opacity-0 transition-opacity duration-[120ms] group-hover:opacity-100 group-focus-within:opacity-100"
          data-role="toolbar"
        >
          <button
            :if={@entry.list_slot == :list}
            id={"#{@entry.id}-list"}
            type="button"
            class={@verb_class}
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark" class="size-4" /> List
          </button>
          <button
            :if={@entry.list_slot == :listed}
            id={"#{@entry.id}-list"}
            type="button"
            class={[@verb_class, "text-base-content/90"]}
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark-solid" class="size-4" /> Listed
          </button>
          <span :if={@entry.list_slot == :following} class={@state_class}>Tracking</span>

          <button
            :if={@entry.download_slot == :download}
            id={"#{@entry.id}-download"}
            type="button"
            class={@verb_class}
            phx-click="feed_download"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download
          </button>
          <span :if={match?({:state, _}, @entry.download_slot)} class={@state_class}>
            <span class={[
              "relative",
              @entry.acquisition_state == :downloading &&
                "after:absolute after:inset-x-0 after:-bottom-[3px] after:h-[3px] after:rounded-sm after:bg-base-content/40"
            ]}>
              {elem(@entry.download_slot, 1)}
            </span>
          </span>

          <button
            :if={not @entry.author.own?}
            id={"#{@entry.id}-ignore"}
            type="button"
            class={[@verb_class, "ml-2.5"]}
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
