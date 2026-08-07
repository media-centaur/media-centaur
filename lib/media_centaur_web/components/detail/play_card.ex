defmodule MediaCentaurWeb.Components.Detail.PlayCard do
  @moduledoc """
  The detail modal's play control — a thin progress bar with optional
  "remaining" text, over the Play/Resume button.

  Play is the **only button in the modal**. Switching what the body shows
  is a view change, not an action, and lives in `Detail.ViewTabs` below;
  this component carries the one thing a user actually *does* here.

  The label ("Play", "Resume Episode 5", "Watch again", …) comes from
  `Detail.Logic.playback_props/3` — no decisions are made at render time.
  When `available` is false (storage offline) the button is replaced with a
  disabled "Offline" pill.

  The row *is* the `detail_actions` nav zone (UIDR-019): LEFT/RIGHT walks
  Play → the link → Manage, DOWN enters the body at the resume target.

  For TV series the progress row is suppressed by the caller (percent 0) —
  series progress lives in the hero orientation block instead.
  """

  use MediaCentaurWeb, :html

  attr :on_play, :string, required: true
  attr :target_id, :string, required: true
  attr :label, :string, required: true
  attr :percent, :integer, default: 0
  attr :remaining_text, :string, default: nil
  attr :available, :boolean, default: true

  slot :controls, doc: "view controls rendered on Play's line — see `Detail.ViewControls`."

  def play_card(assigns) do
    has_progress = assigns.percent > 0
    assigns = assign(assigns, :has_progress, has_progress)

    ~H"""
    <div class="space-y-3 pt-1">
      <div :if={@has_progress} class="space-y-1">
        <div class="flex items-center gap-3">
          <div class="flex-1 h-1 rounded-full bg-base-content/10 overflow-hidden">
            <div
              class={"h-full rounded-full #{if @percent >= 100, do: "bg-success", else: "bg-info"}"}
              style={"width: #{@percent}%"}
            />
          </div>
          <span :if={@remaining_text} class="text-xs text-base-content/40 flex-shrink-0">
            {@remaining_text}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2" data-nav-zone="detail_actions">
        <.button
          :if={@available}
          variant="primary"
          size="sm"
          phx-click={@on_play}
          phx-value-id={@target_id}
          data-nav-item
          data-entity-id={@target_id}
          tabindex="0"
        >
          <.icon name="hero-play-mini" class="size-4" /> {@label}
        </.button>
        <.button
          :if={!@available}
          variant="dismiss"
          size="sm"
          class="text-base-content/40 cursor-not-allowed pointer-events-none"
          title="Storage offline — check that your media drive is mounted"
        >
          <.icon name="hero-cloud-arrow-down-mini" class="size-4 opacity-60" /> Offline
        </.button>
        {render_slot(@controls)}
      </div>
    </div>
    """
  end
end
