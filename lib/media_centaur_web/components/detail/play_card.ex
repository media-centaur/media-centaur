defmodule MediaCentaurWeb.Components.Detail.PlayCard do
  @moduledoc """
  The detail modal's play control — the Play/Resume button, or the
  disabled Offline pill when storage is offline.

  One primary among the action row's four (`Detail.Logic.primary_action/2`):
  the row itself — the `detail_actions` nav zone, the view controls, the
  Download control an unowned title gets instead — belongs to
  `DetailPanel`; this component carries the one thing a person actually
  *does* with an owned title.

  The card carries no progress element (UIDR-024): every subject's
  watched fraction renders in the hero orientation hairline
  (`MediaCentaurWeb.Components.ProgressHairline`), and the remaining time
  is a metadata-line item.

  The label ("Play", "Resume Episode 5", "Watch again", …) comes from
  `Detail.Logic.playback_props/3` — no decisions are made at render time.
  """

  use MediaCentaurWeb, :html

  attr :on_play, :string, required: true
  attr :target_id, :string, required: true
  attr :label, :string, required: true
  attr :available, :boolean, default: true

  def play_card(assigns) do
    ~H"""
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
      data-tip="Storage offline — check that your media drive is mounted"
    >
      <.icon name="hero-cloud-arrow-down-mini" class="size-4 opacity-60" /> Offline
    </.button>
    """
  end
end
