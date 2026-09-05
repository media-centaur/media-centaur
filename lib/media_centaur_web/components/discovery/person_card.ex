defmodule MediaCentaurWeb.Components.Discovery.PersonCard do
  @moduledoc """
  One person on the Friends tab (UIDR-031): the name as the card's
  title, the presence line on the right, a *Recently watched* strip of
  up to #{5} posters with an "all N" tile that grows the strip in
  place, then Tracking and Recommended as text rows of up to #{3} names
  and "N more", Recommended carrying the sentiment glyph. A friend's
  footer holds the elided key, the added date and Remove friend; the
  You card has a primary-tinted border, a subtitle, and no footer. A
  person with nothing shared collapses to header and footer.

  Pure rendering of a `Person`. Every poster and name is a nav item
  that bubbles `open_title` with the title's ref *and* the activity, so
  the modal shows that person's act; `expand_person` and `remove_friend`
  bubble the same way.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.Components.Discovery.Person.Entry
  alias MediaCentaurWeb.DiscoveryLive.Logic

  @strip_cap 5
  @row_cap 3

  attr :person, Person, required: true
  attr :expanded?, :boolean, default: false, doc: "every shelf in full; the host keeps the set"

  def person_card(assigns) do
    assigns =
      assign(assigns,
        watched: shown(assigns.person.watched, @strip_cap, assigns.expanded?),
        tracking: shown(assigns.person.tracking, @row_cap, assigns.expanded?),
        recommended: shown(assigns.person.recommended, @row_cap, assigns.expanded?),
        watched_hidden: hidden(assigns.person.watched, @strip_cap, assigns.expanded?),
        tracking_hidden: hidden(assigns.person.tracking, @row_cap, assigns.expanded?),
        recommended_hidden: hidden(assigns.person.recommended, @row_cap, assigns.expanded?)
      )

    ~H"""
    <section
      id={@person.id}
      class={[
        "glass-surface space-y-3 rounded-xl px-4 py-4",
        @person.own? && "border-primary/30"
      ]}
      data-component="person-card"
      data-own={@person.own?}
    >
      <header class="flex items-center gap-3">
        <span
          class="grid size-10 shrink-0 place-items-center rounded-full bg-primary/15 text-base font-semibold text-primary"
          aria-hidden="true"
        >
          {String.first(@person.name)}
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="truncate text-lg font-semibold leading-tight">{@person.name}</h2>
          <p :if={@person.own?} class="text-xs text-base-content/55">
            {own_subtitle(@person)}
          </p>
        </div>
        <div :if={@person.presence} class="shrink-0 text-right text-sm" data-role="presence">
          <div>{@person.presence.text}</div>
          <div class="text-xs text-base-content/55">{@person.presence.ago}</div>
        </div>
        <span :if={!@person.presence && !@person.own?} class="shrink-0 text-sm text-base-content/55">
          Nothing shared yet
        </span>
      </header>

      <div :if={@person.watched != []} class="space-y-2">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
          Recently watched
        </h3>
        <div class="grid grid-cols-6 gap-2" data-role="watched-strip">
          <button
            :for={entry <- @watched}
            id={"#{@person.id}-watched-#{entry.activity_id}"}
            type="button"
            class="relative aspect-[2/3] cursor-pointer overflow-hidden rounded-md bg-base-content/10"
            title={@person.name <> " watched " <> episode_and_title(entry)}
            phx-click="open_title"
            phx-value-ref={Logic.title_ref_param(entry.ref)}
            phx-value-activity={entry.activity_id}
            data-entity-id={Logic.title_ref_param(entry.ref)}
            data-nav-item
            tabindex="0"
          >
            <img
              :if={entry.poster_url}
              src={sized_image_url(entry.poster_url, 160)}
              alt={entry.title.name}
              class="h-full w-full object-cover"
              loading="eager"
              decoding="sync"
            />
            <span
              :if={!entry.poster_url}
              class="flex h-full w-full items-end p-1.5 text-left text-[10px] leading-tight text-base-content/70"
            >
              {entry.title.name}
            </span>
            <span
              :if={entry.episode}
              class="absolute left-1 top-1 rounded-full bg-neutral/80 px-1.5 text-[10px] font-medium leading-4 text-neutral-content"
            >
              {Format.episode_label(entry.episode.season_number, entry.episode.episode_number)}
            </span>
          </button>
          <button
            :if={@watched_hidden > 0}
            id={"#{@person.id}-watched-all"}
            type="button"
            class="glass-inset grid aspect-[2/3] cursor-pointer place-items-center rounded-md text-xs text-base-content/60"
            phx-click="expand_person"
            phx-value-id={@person.id}
            data-nav-item
            tabindex="0"
          >
            all {length(@person.watched)}
          </button>
        </div>
      </div>

      <.shelf_row
        :if={@person.tracking != []}
        label="Tracking"
        person={@person}
        entries={@tracking}
        hidden={@tracking_hidden}
        verb="is tracking"
      />
      <.shelf_row
        :if={@person.recommended != []}
        label="Recommended"
        person={@person}
        entries={@recommended}
        hidden={@recommended_hidden}
        verb="recommended"
      />

      <footer
        :if={!@person.own?}
        class="flex items-center justify-between border-t border-base-content/10 pt-3"
      >
        <span class="text-xs text-base-content/55">
          <code>{@person.short_npub}</code> · added {Calendar.strftime(@person.added_on, "%b %-d")}
        </span>
        <.button
          variant="dismiss"
          size="xs"
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

  attr :label, :string, required: true
  attr :person, Person, required: true
  attr :entries, :list, required: true, doc: "the `Person.Entry` structs shown, already capped"
  attr :hidden, :integer, required: true, doc: "how many the cap hid; 0 shows no N more"
  attr :verb, :string, required: true

  defp shelf_row(assigns) do
    ~H"""
    <div class="flex items-baseline gap-3 text-sm">
      <span class="w-24 shrink-0 text-xs font-medium uppercase tracking-wider text-base-content/55">
        {@label}
      </span>
      <span class="min-w-0 flex-1">
        <span :for={{entry, index} <- Enum.with_index(@entries)}>
          <span :if={index > 0} class="text-base-content/40"> · </span>
          <button
            id={"#{@person.id}-#{entry.activity_id}"}
            type="button"
            class="cursor-pointer hover:underline"
            title={@person.name <> " " <> @verb <> " " <> entry.title.name}
            phx-click="open_title"
            phx-value-ref={Logic.title_ref_param(entry.ref)}
            phx-value-activity={entry.activity_id}
            data-entity-id={Logic.title_ref_param(entry.ref)}
            data-nav-item
            tabindex="0"
          >
            {entry.title.name}<.icon
              :if={entry.sentiment}
              name={sentiment_glyph(entry.sentiment)}
              class={"ml-1 inline size-3.5 align-[-2px]" <> if(entry.sentiment == :love, do: " text-love", else: "")}
            />
          </button>
        </span>
        <button
          :if={@hidden > 0}
          type="button"
          class="cursor-pointer text-base-content/55 hover:underline"
          phx-click="expand_person"
          phx-value-id={@person.id}
          data-nav-item
          tabindex="0"
        >
          <span class="text-base-content/40"> · </span>{@hidden} more
        </button>
      </span>
    </div>
    """
  end

  defp shown(entries, _cap, true), do: entries
  defp shown(entries, cap, false), do: Enum.take(entries, cap)

  defp hidden(_entries, _cap, true), do: 0
  defp hidden(entries, cap, false), do: max(length(entries) - cap, 0)

  defp sentiment_glyph(:love), do: "hero-heart-solid"
  defp sentiment_glyph(:like), do: "hero-hand-thumb-up"

  defp episode_and_title(%Entry{episode: nil, title: title}), do: title.name

  defp episode_and_title(%Entry{episode: episode, title: title}),
    do: Format.episode_label(episode.season_number, episode.episode_number) <> " of " <> title.name

  defp own_subtitle(%Person{presence: nil}),
    do:
      "Friends see here what you recommend from a title's page, and what you watch and track once sharing is on under Settings → Social."

  defp own_subtitle(_person), do: "How friends see you"
end
