defmodule MediaCentaurWeb.Storybook.PlayOverlay.PlayOverlay do
  @moduledoc """
  Hover-revealed direct-play affordance for browse cards (UIDR-027).

  ## Contract shape (typed)

    * `entity_id` — string, required; fired as `phx-value-id` on the
      shared `"play"` event.
    * `size` — `:sm` (52px, poster cards) | `:lg` (64px, the wide
      continue-watching backdrop). Default `:sm`.

  Both sizes share one treatment: a soft radial halo behind the button
  for glyph legibility (it scales with the card via `closest-side`).

  ## Variation matrix

  One variation per size the app ships. The overlay is invisible at
  rest by design — **hover the framed area and wait out the
  hover-intent delay** to reveal it (the reveal is pointer-hover-only,
  so keyboard/gamepad focus never surfaces it).
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.PlayOverlay.play_overlay/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :poster_card,
        description: "Poster card — 52px button with radial halo. Hover the frame to reveal.",
        attributes: %{entity_id: "sample-entity-id"},
        template: """
        <div class="play-overlay-host relative w-[172px] aspect-[2/3] rounded-lg overflow-hidden glass-inset">
          <.psb-variation/>
        </div>
        """
      },
      %Variation{
        id: :backdrop_card,
        description:
          "Continue-watching backdrop — 64px button, same halo scaled to the wide card. Hover the frame to reveal.",
        attributes: %{entity_id: "sample-entity-id", size: :lg},
        template: """
        <div class="play-overlay-host relative w-[453px] aspect-[16/9] rounded-lg overflow-hidden glass-inset">
          <.psb-variation/>
        </div>
        """
      }
    ]
  end
end
