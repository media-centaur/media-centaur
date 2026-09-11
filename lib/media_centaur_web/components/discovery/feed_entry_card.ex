defmodule MediaCentaurWeb.Components.Discovery.FeedEntryCard do
  @moduledoc """
  One entry on the Feed (UIDR-038): a glass card, the poster at 48×72 on
  the left and to its right three lines at most — who did what and when
  (`Nick recommended ♥ · 2h ago`), which title (name and year), and the
  note when a recommendation has one. A listing and a recommendation are
  one anatomy; the note line is the only difference. Nothing else is on
  the body: no pennant, no marker, no synopsis, no avatar; the rose
  heart after "recommended" for Love is the only colour.

  The toolbar is a fixed 20px seat at the bottom of the text block,
  empty at rest and shown while the card is hovered or holds focus, so
  hover never changes the card's height. Left to right: the List slot
  (the bookmark verb, "Listed" filled, or "Following" as plain state),
  the Download slot (the verb, or plain state text — "Downloading" with
  a hairline, "In library"), and Ignore. State and verb are one control.

  Pure rendering of a `FeedEntry`; the card decides nothing. The whole
  card bubbles `open_title` with the ref and the activity; the verbs
  bubble `feed_list`, `feed_download` and `ignore_title` with the
  activity id. A `div[role=button]` because a button may not contain
  controls. Ships mouse-only: no nav items until the hardening pass.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef

  @verb_class "inline-flex h-5 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-md px-1.5 hover:bg-base-content/10 hover:text-base-content/90"
  @state_class "inline-flex h-5 items-center whitespace-nowrap px-1.5 text-base-content/60"

  attr :entry, FeedEntry, required: true

  def feed_entry_card(assigns) do
    assigns = assign(assigns, verb_class: @verb_class, state_class: @state_class)

    ~H"""
    <div
      id={@entry.id}
      role="button"
      class="glass-surface group flex w-full cursor-pointer items-start gap-3.5 overflow-hidden rounded-xl px-4 pb-2.5 pt-3 text-left"
      data-component="feed-entry"
      data-kind={@entry.kind}
      data-list-slot={@entry.list_slot}
      data-download-slot={slot_name(@entry.download_slot)}
      phx-click="open_title"
      phx-value-ref={TitleRef.param(@entry.ref)}
      phx-value-activity={@entry.activity_id}
      data-entity-id={TitleRef.param(@entry.ref)}
    >
      <div class="h-18 w-12 shrink-0 overflow-hidden rounded-md bg-base-content/10">
        <img
          :if={@entry.poster_url}
          src={sized_image_url(@entry.poster_url, 160)}
          alt=""
          class="h-full w-full object-cover"
          loading="eager"
          decoding="sync"
        />
      </div>

      <div class="flex min-h-18 min-w-0 flex-1 flex-col self-stretch">
        <p class="truncate text-[13px] leading-snug text-base-content/70" data-role="who">
          <span class="font-medium text-base-content/90">{@entry.nickname}</span>
          {ActivityWords.verb(@entry.kind, nil)}
          <span :if={@entry.sentiment == :love} data-role="love">
            <.icon name="hero-heart-solid" class="inline size-3 align-[-1px] text-love" />
          </span>
          <span class="text-base-content/40">·</span>
          <span class="text-base-content/55">{@entry.ago}</span>
        </p>
        <p class="flex items-baseline gap-2 text-sm leading-snug" data-role="title">
          <span class="truncate font-semibold">{@entry.title.name}</span>
          <span :if={@entry.title.year} class="shrink-0 text-xs text-base-content/55">
            {@entry.title.year}
          </span>
        </p>
        <p
          :if={@entry.note}
          class="mb-1 mt-1 line-clamp-4 text-[13px] leading-normal text-base-content/70"
          data-role="note"
        >
          {@entry.note}
        </p>

        <div
          class="-mx-1.5 mt-auto flex h-5 items-center gap-0.5 text-xs text-base-content/70 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100"
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
            <.icon name="hero-bookmark" class="size-3.5" /> List
          </button>
          <button
            :if={@entry.list_slot == :listed}
            id={"#{@entry.id}-list"}
            type="button"
            class={[@verb_class, "text-base-content/90"]}
            phx-click="feed_list"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-bookmark-solid" class="size-3.5" /> Listed
          </button>
          <span :if={@entry.list_slot == :following} class={@state_class}>Following</span>

          <button
            :if={@entry.download_slot == :download}
            id={"#{@entry.id}-download"}
            type="button"
            class={@verb_class}
            phx-click="feed_download"
            phx-value-activity={@entry.activity_id}
          >
            <.icon name="hero-arrow-down-tray" class="size-3.5" /> Download
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
            id={"#{@entry.id}-ignore"}
            type="button"
            class={[@verb_class, "ml-auto"]}
            phx-click="ignore_title"
            phx-value-activity={@entry.activity_id}
          >
            Ignore
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp slot_name(:download), do: "download"
  defp slot_name({:state, word}), do: word
end
