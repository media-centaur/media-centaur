defmodule MediaCentaurWeb.Components.Acquisition.PursuitModal do
  @moduledoc """
  Modal shell for the pursuit detail view, opened from the Incoming
  Activity zone when a pursuit row is clicked.

  A tenant of the cinematic modal frame (`CinematicShell`), so a
  pursued title reads as the same surface as one in the library: fixed
  backdrop, hero window, pinned identity lockup (`PursuitHeader`), with
  the work surface — search facts, unit board, activity / decision
  card, timeline — as the scrolling body. The frame keeps the bare
  modal in the DOM while closed so the `backdrop-filter` compositing
  layer stays warm.

  The host LiveView owns the open/closed state, drives it via the
  `?selected=<pursuit_id>` URL param, and provides the view-models.
  This component is pure rendering.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Components.Acquisition.{
    DecisionCard,
    PursuitActivity,
    PursuitHeader,
    PursuitTimeline,
    UnitBoard
  }

  alias MediaCentaurWeb.Components.CinematicShell

  attr :open, :boolean, required: true

  attr :pursuit_id, :string,
    default: nil,
    doc: "Ecto.UUID of the open pursuit, or nil when closed. Carried for storybook clarity."

  attr :header, :any, default: nil, doc: "%PursuitHeader{} | nil — the title/state/recipe block."
  attr :status, :any, default: nil, doc: "%PursuitStatus{} | nil — the current_action + actions."

  attr :timeline, :any,
    default: nil,
    doc: "%Timeline{} | nil — chronological pursuit events."

  attr :decision_card, :any,
    default: nil,
    doc: "%DecisionCard{} | nil — only present when the pursuit is awaiting a decision."

  attr :unit_board, :any,
    default: nil,
    doc:
      "%UnitBoard{} | nil — per-unit drill-down for composite pursuits (ADR-055). Renders nothing for single-unit pursuits."

  attr :board_expanded_seasons, MapSet,
    default: nil,
    doc: "Expanded season-group keys for the unit board. Nil = each group's exception-driven default."

  attr :on_toggle_season, :string,
    default: "toggle_board_season",
    doc: "Season-header toggle event for the unit board's roll-up."

  attr :client_url, :string,
    default: nil,
    doc:
      "Download client web-UI URL for the status VM's protocol slot — forwarded to the Activity card's \"Open <client>\" link on error states."

  attr :not_found?, :boolean, default: false

  attr :on_close, :string, default: "close_pursuit"
  attr :on_cancel, :string, default: "cancel_pursuit"

  attr :on_change_target, :string,
    default: "request_decision",
    doc:
      "Unit-board swap event — opens the per-unit release picker (decision card); the blind auto-pivot is no longer a UI verb."

  attr :on_request_decision, :string, default: "request_decision"

  def pursuit_modal(assigns) do
    ~H"""
    <%!-- No close-X — backdrop click and Escape both close, and the
          URL preserves history so browser-back also works. The frame
          renders both backdrop copies from the header's backdrop_url
          (nil — no cached artwork yet, or a query-door pursuit —
          renders the quiet placeholder in the hero window). --%>
    <CinematicShell.cinematic_shell
      id="pursuit-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close={@on_close}
      present={@header != nil || @not_found?}
      backdrop_url={@header && @header.backdrop_url}
      scroll_key={@pursuit_id}
      view_key={:main}
      data-pursuit-modal
      data-detail-mode={@open && "modal"}
      data-dismiss-event={@on_close}
    >
      <:orientation>
        <PursuitHeader.pursuit_header :if={@header} vm={@header} />
      </:orientation>
      <:body>
        <div :if={@not_found?} class="p-8 text-center text-sm text-base-content/60">
          Pursuit not found.
        </div>

        <div :if={@header} class="space-y-4 px-1 pt-2 pb-4">
          <PursuitHeader.pursuit_facts vm={@header} />

          <UnitBoard.unit_board
            vm={@unit_board}
            expanded_seasons={@board_expanded_seasons}
            on_toggle_season={@on_toggle_season}
            on_change_target={@on_change_target}
          />

          <%!-- Activity hides when the pursuit is awaiting a decision
              (decision_card present). In that case the Decision
              card carries the prompt and ALL actions, so the
              Activity card would otherwise duplicate the heading,
              meta-narrate the layout ("use the decision card
              below…"), and float Cancel pursuit in a weird spot. --%>
          <PursuitActivity.pursuit_activity
            :if={@status && !@decision_card}
            vm={@status}
            client_url={@client_url}
            on_cancel={@on_cancel}
            on_request_decision={@on_request_decision}
          />

          <DecisionCard.decision_card
            :if={@decision_card}
            vm={@decision_card}
            on_cancel={@on_cancel}
          />

          <PursuitTimeline.timeline :if={@timeline} vm={@timeline} />
        </div>
      </:body>
    </CinematicShell.cinematic_shell>
    """
  end
end
