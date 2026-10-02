defmodule MediaCentaurWeb.Components.Title.Row do
  @moduledoc """
  One title row — a watchlist entry or a media-search result — as a
  whole-card click target opening the title detail modal (spec
  2026-09-05 §14). The shared `title_summary/1` identity block, the
  quiet markers the host computed (`Logic.row_markers/2`), the notes in
  place of the overview — one unattributed note reads plain, several
  carry their names (UIDR-038) — and, at the right, the next release a
  followed title carries (`NextRelease`: its date, the release and its
  `StatusPill` status) and the title's social glyphs: the flags a friend
  flew (`SocialWords.drawn_flags/1`), each at its grade with its
  sentence on hover. State is shown, never acted on here: every verb
  lives in the modal, and the pursuit row an in-pursuit pill names is on
  the Activity tab. (The Feed's rows are `Discovery.FeedRow`, which
  carries its own toolbar.)

  Pure rendering; `open_title` bubbles to the host with the
  title's ref. The ref doubles as `data-entity-id`, the stable identity
  the input system records as the overlay-restore origin, so closing the
  modal lands the cursor back on the row that opened it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Incoming.StatusPill, only: [status_pill: 1]
  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.Components.Title.SocialWords
  alias MediaCentaurWeb.TitleRef

  defmodule NextRelease do
    @moduledoc """
    A followed title's next release, as the row draws it: the date label
    (`UpcomingFeed.date_label/2`), the release (an episode, a
    season drop, a film's date type), the `StatusPill` status, and the
    percent and pursuit id an in-pursuit release carries.
    """
    @enforce_keys [:air_date, :date_label, :status]
    defstruct [:air_date, :date_label, :subtitle, :status, :percent, :pursuit_id]

    @type t :: %__MODULE__{
            air_date: Date.t(),
            date_label: String.t(),
            subtitle: String.t() | nil,
            status: :armed | :in_pursuit | :in_theaters | :tracked | :searching | :landed,
            percent: integer() | nil,
            pursuit_id: Ecto.UUID.t() | nil
          }
  end

  attr :id, :string, required: true
  attr :title, Title, required: true

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`"

  attr :markers, :list, default: [], doc: "quiet text markers from `Logic.row_markers/2`"

  attr :notes, :list,
    default: [],
    doc: "`%{name: nil | String.t(), text}` notes displacing the overview; a lone nil name reads plain"

  attr :social_activity, :list,
    default: [],
    doc: "the title's `Activities.activity_for/1` rows — the social glyphs at the row's right"

  attr :next_release, NextRelease,
    default: nil,
    doc:
      "a followed title's next release — date, release and status at the row's right; nil for a listed-only title"

  def title_row(assigns) do
    rows = assigns.social_activity

    assigns =
      assign(assigns,
        flags: SocialWords.drawn_flags(rows),
        grades: Grade.for_title(rows),
        sentences: SocialWords.sentences(rows)
      )

    ~H"""
    <div
      id={@id}
      role="button"
      class="glass-surface flex w-full cursor-pointer items-start gap-4 overflow-hidden rounded-xl px-4 py-3 text-left"
      data-component="title-row"
      phx-click="open_title"
      phx-value-ref={TitleRef.param(Title.ref(@title))}
      data-entity-id={TitleRef.param(Title.ref(@title))}
      data-nav-item
      tabindex="0"
    >
      <.title_summary title={@title} poster_url={@poster_url}>
        <:markers>
          <span :for={marker <- @markers} class="shrink-0 text-xs text-base-content/55">
            {marker}
          </span>
        </:markers>
        <:secondary :if={@notes != []}>
          <span :for={note <- @notes} class="block">
            <span :if={note.name} class="font-medium text-base-content/70">{note.name}</span>
            {note.text}
          </span>
        </:secondary>
      </.title_summary>
      <div class="ml-auto flex shrink-0 items-center gap-4 self-center">
        <div :if={@next_release} class="flex flex-col items-end gap-1 text-right">
          <span class="text-xs font-medium text-base-content/55">{@next_release.date_label}</span>
          <span :if={@next_release.subtitle} class="text-xs text-base-content/55">
            {@next_release.subtitle}
          </span>
          <.status_pill status={@next_release.status} percent={@next_release.percent} />
        </div>
        <SocialGlyph.social_glyphs
          :if={@flags != []}
          flags={@flags}
          grades={@grades}
          tips={@sentences}
          class="gap-3 [--glyph:1.25rem]"
        />
      </div>
    </div>
    """
  end
end
