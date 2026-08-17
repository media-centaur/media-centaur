defmodule MediaCentaurWeb.Storybook.PlayOverlay.PlayOverlay do
  @moduledoc """
  Hover-revealed direct-play affordance for browse cards (UIDR-027).

  ## Contract shape (typed)

    * `entity_id` — string, required; fired as `phx-value-id` on the
      shared `"play"` event.
    * `size` — `:sm` (52px, poster cards) | `:lg` (64px, the wide
      continue-watching backdrop). Default `:sm`.
    * `scrim` — `:gradient` (bottom scrim for bare posters) | `:dim`
      (light flat wash for cards that already carry their own
      gradient). Default `:gradient`.

  ## Variation matrix

  One variation per (size, scrim) pairing the app ships: poster cards
  use `:sm`/`:gradient`, the continue-watching backdrop uses
  `:lg`/`:dim`. The overlay is invisible at rest by design — **hover
  the framed area** to reveal it (the reveal is pointer-hover-only, so
  keyboard/gamepad focus never surfaces it).
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.PlayOverlay.play_overlay/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :poster_card,
        description: "Poster card — 52px button, gradient scrim. Hover the frame to reveal.",
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
          "Continue-watching backdrop — 64px button, flat dim (the card carries its own gradient). Hover the frame to reveal.",
        attributes: %{entity_id: "sample-entity-id", size: :lg, scrim: :dim},
        template: """
        <div class="play-overlay-host relative w-[453px] aspect-[16/9] rounded-lg overflow-hidden glass-inset">
          <.psb-variation/>
        </div>
        """
      }
    ]
  end
end
