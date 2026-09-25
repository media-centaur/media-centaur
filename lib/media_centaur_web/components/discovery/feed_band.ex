defmodule MediaCentaurWeb.Components.Discovery.FeedBand do
  @moduledoc """
  One band on the Feed (UIDR-046): one author's action on one title as
  one unit at one size — 1236×224 on ink, no border, glass, shadow or
  hairline. The identity tile at the left edge, the poster at 100×150
  beside it, then the text zone: who did what (`Nick reviewed ♥`, `You
  want to watch`; the sentiment glyph after the verb when the review
  gives one, nothing when it gives none), which title (name and year at
  28px), and the review's words at two lines at most; the relative time
  right-aligned at the text zone's edge. The title's still fills a
  right-hand image box — 536px of the 1236 column, capped at 900 —
  under the ink scrim's 360px dissolve, cropped at `50% 30%`, or `38%`
  on the second of two adjacent bands of one title so one frame never
  repeats exactly. No artwork: the band on the inset tone with a short
  scrim and the poster slot empty. An own band is the filled own tile
  and the second-person verb; nothing else marks it.

  The toolbar is a fixed 32px seat at the bottom of the text zone,
  empty at rest and shown while the band is hovered or holds focus, so
  hover never changes the band's height. Left to right: the List slot
  (the bookmark verb, "Listed" filled, or "Tracking" as plain state),
  the Download slot (the verb, or plain state text — "Downloading" with
  a hairline, "In library"), and Ignore on a friend's band only. State
  and verb are one control. An own band has no Ignore and no Delete:
  withdrawing is the modal's Delete, and the band opens the modal
  speaking for its action.

  Pure rendering of a `FeedEntry`; the band decides nothing. It keeps
  the row's DOM contract — `feed-row-<activity id>`, `data-component=
  "feed-row"`, the slot attributes, the `data-role`s, the control ids —
  so the page's tests are the regression net while the look changes.
  The whole band bubbles `open_title` with the ref and the activity;
  the verbs bubble `feed_list`, `feed_download` and `ignore_title` with
  the activity id. A `div[role=button]` because a button may not
  contain controls. Ships mouse-only: no nav items until the hardening
  pass. Every position is a custom property of `.feed-band`; the text
  is Tailwind on top, at the couch floors.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.Discovery.IdentityTile
  alias MediaCentaurWeb.Components.Title.Sentiment
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef

  @verb_class "inline-flex h-8 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-md px-1.5 hover:bg-base-content/10 hover:text-base-content/90"
  @state_class "inline-flex h-8 items-center whitespace-nowrap px-1.5 text-base-content/65"

  attr :entry, FeedEntry, required: true

  def feed_band(assigns) do
    assigns = assign(assigns, verb_class: @verb_class, state_class: @state_class)

    ~H"""
    <div
      id={@entry.id}
      role="button"
      class={[
        "group feed-band text-left",
        @entry.offset_crop? && "feed-band-offset",
        !@entry.backdrop_url && "feed-band-bare"
      ]}
      data-component="feed-row"
      data-kind={@entry.kind}
      data-own={@entry.own?}
      data-offset-crop={@entry.offset_crop?}
      data-list-slot={@entry.list_slot}
      data-download-slot={slot_name(@entry.download_slot)}
      phx-click="open_title"
      phx-value-ref={TitleRef.param(@entry.ref)}
      phx-value-activity={@entry.activity_id}
      data-entity-id={TitleRef.param(@entry.ref)}
    >
      <img
        :if={@entry.backdrop_url}
        src={band_backdrop_src(@entry.backdrop_url)}
        alt=""
        class="feed-band-backdrop"
        data-role="backdrop"
        loading="eager"
        decoding="sync"
      />
      <div class="feed-band-scrim" aria-hidden="true"></div>

      <span class="feed-band-tile">
        <IdentityTile.identity_tile name={@entry.author} own?={@entry.own?} size={56} />
      </span>

      <img
        :if={@entry.poster_url}
        src={band_poster_src(@entry.poster_url)}
        alt=""
        class="feed-band-poster object-cover"
        data-role="poster"
        loading="eager"
        decoding="sync"
      />
      <div
        :if={!@entry.poster_url}
        class="feed-band-poster bg-base-content/6 ring-1 ring-inset ring-base-content/10"
        data-role="poster-empty"
      >
      </div>

      <div class="feed-band-body text-on-image flex flex-col">
        <p class="truncate text-[22px] leading-[30px] text-base-content/80" data-role="who">
          <span class="font-medium text-base-content/95">{@entry.author}</span>
          {ActivityWords.verb(@entry.kind, nil, subject(@entry))}
          <Sentiment.sentiment_glyph
            :if={@entry.sentiment}
            sentiment={@entry.sentiment}
            class="size-5"
          />
        </p>
        <p class="flex items-baseline gap-2.5 text-[28px] font-semibold leading-9" data-role="title">
          <span class="truncate">{@entry.title.name}</span>
          <span :if={@entry.title.year} class="shrink-0 text-lg font-normal text-base-content/65">
            {@entry.title.year}
          </span>
        </p>
        <p
          :if={@entry.text}
          class="mt-1 line-clamp-2 text-[22px] leading-[30px] text-base-content/80"
          data-role="text"
        >
          {@entry.text}
        </p>

        <div
          class="-mx-1.5 mt-auto flex h-8 items-center gap-0.5 text-lg text-base-content/80 opacity-0 transition-opacity duration-[120ms] group-hover:opacity-100 group-focus-within:opacity-100"
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
            <.icon name="hero-bookmark" class="size-5" /> List
          </button>
          <button
            :if={@entry.list_slot == :listed}
            id={"#{@entry.id}-list"}
            type="button"
            class={[@verb_class, "text-base-content/90"]}
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark-solid" class="size-5" /> Listed
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
            <.icon name="hero-arrow-down-tray" class="size-5" /> Download
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
            :if={not @entry.own?}
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

      <span
        class="feed-band-time text-on-image text-lg tabular-nums text-base-content/80"
        data-role="time"
      >
        {@entry.ago}
      </span>
    </div>
    """
  end

  @doc "The `src` a band's still paints — a 536 CSS px box on a 4K panel — one definition, so a prefetch can match it."
  @spec band_backdrop_src(String.t() | nil) :: String.t() | nil
  def band_backdrop_src(url), do: sized_image_url(url, 1280)

  @doc "The `src` a band's poster paints at 100×150 CSS px."
  @spec band_poster_src(String.t() | nil) :: String.t() | nil
  def band_poster_src(url), do: sized_image_url(url, 240)

  defp subject(%FeedEntry{own?: true}), do: :you
  defp subject(%FeedEntry{}), do: :friend

  defp slot_name(:download), do: "download"
  defp slot_name({:state, word}), do: word
end
