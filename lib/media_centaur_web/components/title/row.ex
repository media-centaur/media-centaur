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

  `ignorable?` adds the Recommendations row's `×`: a one-click shortcut
  to the Ignored rung, the one verb a person reaches for while scanning
  a list rather than reading a title. It is a pointer affordance —
  revealed on hover, never a nav item — because keyboard and gamepad
  already have the same verb on the ladder in the modal. A sibling of
  the card button, not a child: nested buttons are invalid HTML, so the
  row is a frame holding both. Pushes `ignore_title` with the ref.

  Pure rendering; `open_title` bubbles to the host with the
  title's ref. The ref doubles as `data-entity-id`, the stable identity
  the input system records as the overlay-restore origin, so closing the
  modal lands the cursor back on the row that opened it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Title.Pennant,
    only: [pennants: 1]

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]
  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.TitleRef

  attr :id, :string,
    required: true,
    doc: "the card button's id; the frame is `<id>-frame`, the × `<id>-ignore`"

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
    doc: "renders the hover-revealed × that pushes `ignore_title`; the Recommendations tab only"

  def title_row(assigns) do
    ~H"""
    <div id={"#{@id}-frame"} class="group relative">
      <button
        id={@id}
        type="button"
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
            <span :if={@lead} class="shrink-0 text-xs text-base-content/55">{@lead}</span>
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
        <%!-- The mast bleeds into the row's right padding so the hoist
              meets the border; overflow-hidden clips it to the corners. --%>
        <.pennants activity={@friend_activity} class="-mr-4 self-center" />
      </button>
      <%!-- Pointer-only by design: no data-nav-item, tabindex -1. The
            ladder in the modal is the keyboard and gamepad path. It sits
            in the gutter right of the card, centred: the mast owns the
            card's right edge, and a corner placement lands on the top
            pennant's hoist. --%>
      <button
        :if={@ignorable?}
        id={"#{@id}-ignore"}
        type="button"
        class="absolute top-1/2 -right-8 -translate-y-1/2 cursor-pointer rounded-full p-1 text-base-content/55 opacity-0 transition-opacity group-hover:opacity-100 hover:text-base-content/90 focus-visible:opacity-100"
        phx-click="ignore_title"
        phx-value-ref={TitleRef.param(Title.ref(@title))}
        aria-label="Ignore"
        title="Ignore"
        tabindex="-1"
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </button>
    </div>
    """
  end
end
