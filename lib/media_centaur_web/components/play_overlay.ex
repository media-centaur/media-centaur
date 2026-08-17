defmodule MediaCentaurWeb.Components.PlayOverlay do
  @moduledoc """
  Hover-revealed direct-play affordance for browse cards (UIDR-027).

  Renders inside a card's `relative` image region. Invisible at rest, it
  fades in (opacity only, 120ms) while the pointer hovers the nearest
  `.play-overlay-host` ancestor — hover is the only trigger, so the
  affordance does not exist for keyboard/gamepad input. The button fires
  the shared `"play"` event (`MediaCentaur.Playback.play/1` in place —
  no detail modal).

  Deliberately outside the input system: `tabindex="-1"`, no
  `data-nav-item`. Clicks on the button never reach the card's
  `select_entity` — LiveView dispatches to the closest `phx-click`
  binding only.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  attr :entity_id, :string, required: true

  attr :size, :atom,
    values: [:sm, :lg],
    default: :sm,
    doc: "`:sm` (52px) for poster-shaped cards, `:lg` (64px) for the wide backdrop card"

  attr :scrim, :atom,
    values: [:gradient, :dim],
    default: :gradient,
    doc:
      "`:gradient` adds a bottom scrim for glyph legibility on bare posters; " <>
        "`:dim` is a light flat wash for cards that already carry their own gradient"

  def play_overlay(assigns) do
    ~H"""
    <div class={["play-overlay", @scrim == :dim && "play-overlay-dim"]}>
      <button
        type="button"
        class={["play-overlay-btn", @size == :lg && "play-overlay-btn-lg"]}
        phx-click="play"
        phx-value-id={@entity_id}
        tabindex="-1"
        aria-label="Play"
      >
        <.icon
          name="hero-play-solid"
          class={if @size == :lg, do: "size-6 ml-0.5", else: "size-5 ml-0.5"}
        />
      </button>
    </div>
    """
  end
end
