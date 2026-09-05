defmodule MediaCentaurWeb.Components.Detail.PlayCard do
  @moduledoc """
  The detail modal's play control — the Play/Resume button and the view
  controls sharing its line.

  Play is the **only button in the modal**. Switching what the body shows
  is a view change, not an action, and lives in `Detail.ViewControls`;
  this component carries the one thing a user actually *does* here.

  The card carries no progress element (UIDR-024): every subject's
  watched fraction renders in the hero orientation hairline
  (`MediaCentaurWeb.Components.ProgressHairline`), and the remaining time
  is a metadata-line item. The former percent/remaining row was retired
  from this contract, not hidden.

  The label ("Play", "Resume Episode 5", "Watch again", …) comes from
  `Detail.Logic.playback_props/3` — no decisions are made at render time.
  When `available` is false (storage offline) the button is replaced with a
  disabled "Offline" pill.

  The row *is* the `detail_actions` nav zone (UIDR-019): LEFT/RIGHT walks
  Play → the link → Manage, DOWN enters the body at the resume target.
  """

  use MediaCentaurWeb, :html

  attr :on_play, :string, required: true
  attr :target_id, :string, required: true
  attr :label, :string, required: true
  attr :available, :boolean, default: true

  slot :controls, doc: "view controls rendered on Play's line — see `Detail.ViewControls`."

  def play_card(assigns) do
    ~H"""
    <%!-- data-nav-enter-scroll-top: arrowing up out of the body list glides
          the modal back to the hero; BACK lands here without moving it. --%>
    <div
      class="flex items-center gap-2 pt-1"
      data-nav-zone="detail_actions"
      data-nav-enter-scroll-top
    >
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
        class="text-base-content/55 cursor-not-allowed pointer-events-none"
        title="Storage offline — check that your media drive is mounted"
      >
        <.icon name="hero-cloud-arrow-down-mini" class="size-4 opacity-60" /> Offline
      </.button>
      {render_slot(@controls)}
    </div>
    """
  end
end
