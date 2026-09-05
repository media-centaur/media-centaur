defmodule MediaCentaurWeb.Components.Discovery.TitleRow do
  @moduledoc """
  One Discovery row — a title on the Recommendations tab or a watchlist
  entry — as a whole-card click target opening the title detail modal
  (spec 2026-09-05 §14). The shared `title_summary/1` identity block, an
  optional lead line (the Recommendations tab's `<names> · when`), the
  quiet markers the host computed (`DiscoveryLive.Logic.row_markers/1`),
  and the notes in place of the overview: one unattributed note reads
  plain, several carry their names (UIDR-031). State is shown, never
  acted on here: every verb lives in the modal.

  Pure rendering; `open_title` bubbles to `DiscoveryLive` with the
  title's ref. The ref doubles as `data-entity-id`, the stable identity
  the input system records as the overlay-restore origin, so closing the
  modal lands the cursor back on the row that opened it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Discovery.RecommendationPennant,
    only: [recommendation_pennants: 1]

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.Logic

  attr :id, :string, required: true
  attr :title, Title, required: true

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`"

  attr :lead, :string,
    default: nil,
    doc: "the Recommendations tab's names/when line; nil on the watchlist"

  attr :markers, :list, default: [], doc: "quiet text markers from `Logic.row_markers/1`"

  attr :notes, :list,
    default: [],
    doc: "`%{name: nil | String.t(), text}` notes displacing the overview; a lone nil name reads plain"

  attr :recommendations, :list,
    default: [],
    doc: "the title's `Activities.recommendations_for/1` rows — the pennants on the mast"

  def title_row(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="glass-surface flex w-full cursor-pointer items-start gap-4 overflow-hidden rounded-xl px-4 py-3 text-left"
      data-component="title-row"
      phx-click="open_title"
      phx-value-ref={Logic.title_ref_param({@title.tmdb_id, @title.media_type})}
      data-entity-id={Logic.title_ref_param({@title.tmdb_id, @title.media_type})}
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
      <.recommendation_pennants recommendations={@recommendations} class="-mr-4 self-center" />
    </button>
    """
  end
end
