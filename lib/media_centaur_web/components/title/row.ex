defmodule MediaCentaurWeb.Components.Title.Row do
  @moduledoc """
  One title row — a watchlist entry or a media-search result — as a
  whole-card click target opening the title detail modal (spec
  2026-09-05 §14). The shared `title_summary/1` identity block, the
  quiet markers the host computed (`Logic.row_markers/2`), the notes in
  place of the overview — one unattributed note reads plain, several
  carry their names (UIDR-038) — and, at the right, the title's social
  glyphs: the flags a friend flew (`SocialWords.drawn_flags/1`), each at
  its grade with its sentence on hover. State is shown, never acted on
  here: every verb lives in the modal. (The Feed's rows are
  `Discovery.FeedRow`, which carries its own toolbar.)

  Pure rendering; `open_title` bubbles to the host with the
  title's ref. The ref doubles as `data-entity-id`, the stable identity
  the input system records as the overlay-restore origin, so closing the
  modal lands the cursor back on the row that opened it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.Components.Title.SocialGlyph
  alias MediaCentaurWeb.Components.Title.SocialWords
  alias MediaCentaurWeb.TitleRef

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
      <SocialGlyph.social_glyphs
        :if={@flags != []}
        flags={@flags}
        grades={@grades}
        titles={@sentences}
        class="ml-auto gap-3 self-center [--glyph:1.25rem]"
      />
    </div>
    """
  end
end
