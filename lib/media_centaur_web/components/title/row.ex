defmodule MediaCentaurWeb.Components.Title.Row do
  @moduledoc """
  One Discovery row — a title on the Recommendations tab or a watchlist
  entry — as a whole-card click target opening the title detail modal
  (spec 2026-09-05 §14). The shared `title_summary/1` identity block, an
  optional lead line (the Recommendations tab's `<names> · when`), the
  quiet markers the host computed (`Logic.row_markers/2`),
  and the notes in place of the overview: one unattributed note reads
  plain, several carry their names (UIDR-031). State is shown, never
  acted on here: every verb lives in the modal — with one exception.

  `ignorable?` adds the Recommendations row's one verb: "Ignore", quiet
  text at the end of the lead line, a shortcut to the Ignored rung. It
  shows while the row is hovered or holds the cursor, and it is the
  row's `data-nav-sub-item` — the detail modal's episode rows carry
  their watched toggle the same way — so RIGHT steps onto it, SELECT
  activates it and LEFT steps back (the rows zone is a TREE). The card
  is a `div[role=button]` rather than a `<button>` because a button may
  not contain a control. Pushes `ignore_title` with the ref.

  Pure rendering; `open_title` bubbles to the host with the
  title's ref. The ref doubles as `data-entity-id`, the stable identity
  the input system records as the overlay-restore origin, so closing the
  modal lands the cursor back on the row that opened it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Title.Pennant,
    only: [pennants: 1]

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.TitleRef

  attr :id, :string, required: true, doc: "the card's id; the Ignore control is `<id>-ignore`"
  attr :title, Title, required: true

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`"

  attr :lead, :string,
    default: nil,
    doc: "the Recommendations tab's names/when line; nil on the watchlist"

  attr :markers, :list, default: [], doc: "quiet text markers from `Logic.row_markers/2`"

  attr :notes, :list,
    default: [],
    doc: "`%{name: nil | String.t(), text}` notes displacing the overview; a lone nil name reads plain"

  attr :friend_activity, :list,
    default: [],
    doc: "the title's `Activities.friend_activity_for/1` rows — the pennants on the mast"

  attr :ignorable?, :boolean,
    default: false,
    doc: "renders the Ignore sub-item that pushes `ignore_title`; the Recommendations tab only"

  def title_row(assigns) do
    ~H"""
    <div
      id={@id}
      role="button"
      class="glass-surface group flex w-full cursor-pointer items-start gap-4 overflow-hidden rounded-xl px-4 py-3 text-left"
      data-component="title-row"
      phx-click="open_title"
      phx-value-ref={TitleRef.param(Title.ref(@title))}
      data-entity-id={TitleRef.param(Title.ref(@title))}
      data-nav-item
      tabindex="0"
    >
      <.title_summary title={@title} poster_url={@poster_url}>
        <:markers>
          <span :if={@lead} class="shrink-0 text-xs text-base-content/55">{@lead}</span>
          <span :for={marker <- @markers} class="shrink-0 text-xs text-base-content/55">
            {marker}
          </span>
          <%!-- Hidden until the row is hovered or holds the cursor, so RIGHT
                has a visible target before the press. --%>
          <button
            :if={@ignorable?}
            id={"#{@id}-ignore"}
            type="button"
            class="shrink-0 cursor-pointer rounded-full px-1 text-xs text-base-content/70 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100 hover:text-base-content/90 hover:underline hover:underline-offset-3"
            phx-click="ignore_title"
            phx-value-ref={TitleRef.param(Title.ref(@title))}
            data-nav-sub-item
            tabindex="-1"
          >
            Ignore
          </button>
        </:markers>
        <:secondary :if={@notes != []}>
          <span :for={note <- @notes} class="block">
            <span :if={note.name} class="font-medium text-base-content/70">{note.name}</span>
            {note.text}
          </span>
        </:secondary>
      </.title_summary>
      <%!-- The mast bleeds into the row's right padding so the hoist
            meets the border; overflow-hidden clips it to the corners. --%>
      <.pennants activity={@friend_activity} class="-mr-4 self-center" />
    </div>
    """
  end
end
