defmodule MediaCentaurWeb.Components.Acquisition.PursuitModal do
  @moduledoc """
  Modal shell for the pursuit detail view, opened from the Downloads
  index (`/download`) when a pursuit row is clicked.

  Always present in the DOM so the browser keeps the `backdrop-filter`
  compositing layer warm. Toggled via `data-state="open"/"closed"` — no
  first-frame blur jank on open. Mirrors `ModalShell`'s pattern for the
  Library entity detail; the contents are pursuit-specific
  (header / activity / decision card / timeline).

  The host LiveView owns the open/closed state, drives it via the
  `?selected=<pursuit_id>` URL param, and provides the four view-models.
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
    <.modal
      id="pursuit-modal"
      open={@open}
      dismiss={:ephemeral}
      on_close={@on_close}
      data-pursuit-modal
    >
      <%!-- No close-X — backdrop click and Escape both close, and the
            URL preserves history so browser-back also works. --%>
      <%!-- Same panel-level treatment as the library detail modal: the
            backdrop spans 70% of the scroll height fading into the panel,
            the atmosphere dim covers the full scroll height, and the
            header/content flow over both (z-2). The header renders only
            the overlaid identity facts — or its synthetic gradient when
            no artwork is cached. --%>
      <div class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden relative thin-scrollbar">
        <div :if={@not_found?} class="p-8 text-center text-sm text-base-content/60">
          Pursuit not found.
        </div>

        <div
          :if={!@not_found? && @header && @header.backdrop_url}
          class="modal-page-backdrop modal-page-backdrop--early-fade"
          aria-hidden="true"
        >
          <img src={@header.backdrop_url} alt="" loading="eager" decoding="sync" fetchpriority="high" />
        </div>

        <div :if={!@not_found? && @header} class="modal-page-content">
          <div :if={@header.backdrop_url} class="modal-page-atmosphere" aria-hidden="true"></div>

          <div class="relative z-[2] pb-6 space-y-4">
            <PursuitHeader.pursuit_header vm={@header} />

            <div class="px-6 space-y-4">
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
          </div>
        </div>
      </div>
    </.modal>
    """
  end
end
