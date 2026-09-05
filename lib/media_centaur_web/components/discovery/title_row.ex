defmodule MediaCentaurWeb.Components.Discovery.TitleRow do
  @moduledoc """
  One Discovery row — a recommendation on the feed or a watchlist entry —
  as a whole-card click target opening the title detail modal (spec
  2026-09-05 §14). The shared `title_summary/1` identity block, an
  optional lead line (the feed's `from <nickname> · when` / `You · when`),
  the quiet markers the host computed (`DiscoveryLive.Logic.row_markers/1`),
  and the secondary text (a note) in place of the overview. State is
  shown, never acted on here: every verb lives in the modal.

  Pure rendering; `open_title` bubbles to `DiscoveryLive` with the
  title's ref. The ref doubles as `data-entity-id`, the stable identity
  the input system records as the overlay-restore origin, so closing the
  modal lands the cursor back on the row that opened it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.TMDB.TitleSummary, only: [title_summary: 1]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.DiscoveryLive.Logic

  attr :id, :string, required: true
  attr :title, Title, required: true

  attr :poster_url, :string,
    default: nil,
    doc: "resolved by the host via `LiveHelpers.title_poster_url/1`"

  attr :lead, :string, default: nil, doc: "the feed's sender/when line; nil on the watchlist"
  attr :markers, :list, default: [], doc: "quiet text markers from `Logic.row_markers/1`"
  attr :secondary, :string, default: nil, doc: "a note that displaces the overview"

  def title_row(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="glass-surface flex w-full cursor-pointer items-start gap-4 rounded-xl px-4 py-3 text-left"
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
        <:secondary :if={@secondary}>{@secondary}</:secondary>
      </.title_summary>
    </button>
    """
  end
end
