defmodule MediaCentarrWeb.Components.Acquisition.PursuitModal do
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

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.Components.Acquisition.{
    DecisionCard,
    PursuitActivity,
    PursuitHeader,
    PursuitTimeline
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

  attr :not_found?, :boolean, default: false

  attr :on_close, :string, default: "close_pursuit"
  attr :on_cancel, :string, default: "cancel_pursuit"
  attr :on_change_target, :string, default: "change_target"
  attr :on_request_decision, :string, default: "request_decision"

  def pursuit_modal(assigns) do
    ~H"""
    <div
      id="pursuit-modal"
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      data-pursuit-modal
      phx-click={@open && @on_close}
      phx-window-keydown={@open && @on_close}
      phx-key="Escape"
    >
      <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
        <%!-- No close-X — backdrop click and Escape both close, and the
              URL preserves history so browser-back also works. --%>
        <div class="flex-1 min-h-0 overflow-y-auto overflow-x-hidden thin-scrollbar">
          <div :if={@not_found?} class="p-8 text-center text-sm text-base-content/60">
            Pursuit not found.
          </div>

          <div :if={!@not_found? && @header} class="p-6 space-y-4">
            <PursuitHeader.pursuit_header vm={@header} />

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
              on_change_target={@on_change_target}
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
    """
  end
end
