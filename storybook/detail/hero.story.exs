defmodule MediaCentaurWeb.Storybook.Detail.Hero do
  @moduledoc """
  Detail-panel hero window — the transparent 21:9 frame at the top of
  the detail document. The panel-level *fixed* backdrop shows through
  it; the identity lockup and season hairline live in the orientation
  block below (see `DetailPanel`), which overlaps this frame at rest
  and pins on scroll (2026-08-05 sticky-orientation design).

  The component renders only two things of its own:

    * a quiet film placeholder filling the frame when the entity has
      neither a `"backdrop"` nor a `"poster"` image, or when
      `available: false` — see `:missing_artwork` / `:unavailable`;
    * the top-right `actions` overlay (tracking bell) — see
      `:with_actions`.

  With artwork present and no actions, the frame is intentionally
  empty — `:with_backdrop` shows it against the template's stand-in
  backdrop, exactly the see-through state the real modal composes.

  Image fixtures use minimally-shaped maps
  (`%{role: "...", content_url: "..."}`); `image_url/2` reads only
  those two fields.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.Hero.hero/1
  def render_source, do: :function
  def layout, do: :one_column

  # Full-bleed frame; the template paints a stand-in backdrop behind it
  # (the real one lives at the modal-panel level). Iframe isolation
  # keeps each variation's backdrop confined to its own preview.
  def container, do: {:iframe, style: "min-height: 360px; width: 100%;"}

  def template do
    """
    <div class="relative bg-base-100 min-h-[340px] overflow-hidden">
      <img
        src="https://placehold.co/1920x820/1a1a1a/333333?text=Modal+backdrop"
        alt=""
        aria-hidden="true"
        class="absolute inset-0 w-full h-full object-cover opacity-60"
      />
      <div class="relative z-[1] p-4 max-w-4xl mx-auto">
        <.psb-variation/>
      </div>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :with_backdrop,
        description:
          "Happy path — entity has a `\"backdrop\"` image, so the placeholder is " <>
            "suppressed and the frame is a transparent window onto the " <>
            "(template-level) backdrop.",
        attributes: %{
          entity: entity_with_artwork(),
          available: true
        }
      },
      %Variation{
        id: :missing_artwork,
        description:
          "No backdrop, no poster (`images: []`) — the 21:9 frame fills with the " <>
            "`hero-film` placeholder icon.",
        attributes: %{
          entity: entity_without_artwork(),
          available: true
        }
      },
      %Variation{
        id: :with_actions,
        description:
          "Exercises the `actions` slot with a tracking-bell-style button — " <>
            "rendered absolutely positioned in the top-right of the 21:9 frame.",
        attributes: %{
          entity: entity_with_artwork(),
          available: true
        },
        slots: [
          ~s|<:actions><button type="button" class="btn btn-circle btn-sm btn-ghost"><span class="hero-bell size-4"></span></button></:actions>|
        ]
      },
      %Variation{
        id: :unavailable,
        description:
          "`available: false` (storage offline / file missing) — the placeholder " <>
            "renders even when the entity has artwork.",
        attributes: %{
          entity: entity_with_artwork(),
          available: false
        }
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  defp entity_with_artwork do
    %{
      name: "Sample Show",
      images: [
        %{role: "backdrop", content_url: "fixtures/hero-backdrop.jpg"}
      ]
    }
  end

  defp entity_without_artwork do
    %{
      name: "Sample Show",
      images: []
    }
  end
end
