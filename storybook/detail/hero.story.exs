defmodule MediaCentarrWeb.Storybook.Detail.Hero do
  @moduledoc """
  21:9 detail-panel hero — the title-layer frame that sits on top of
  the modal-panel backdrop.

  This component itself is **transparent**: it only renders the logo
  (or title fallback), the optional tagline, and a top-right `actions`
  slot. The backdrop image and atmospheric scrims live at the parent
  `ModalShell` level. The story's template recreates that context with
  a `placehold.co` backdrop so the previews show the hero against
  realistic artwork rather than an empty void.

  Behaviour the variations pin:

    * When the entity has neither a `"backdrop"` nor a `"poster"` image
      (or `available: false`), the 21:9 frame fills with a quiet film
      placeholder icon — see `:missing_artwork` and `:unavailable`.
    * The logo `<img>` only renders when a `"logo"` image exists *and*
      `available` is true; otherwise the entity name renders as an
      `<h2>` fallback — see `:without_logo`.
    * The tagline `<p>` only renders when `tagline` is non-nil and
      non-empty — see `:no_tagline`.
    * The `actions` slot renders absolutely-positioned in the top-right
      corner when given; absent or empty slot suppresses the wrapper —
      see `:with_actions`.

  Image fixtures use minimally-shaped maps `(%{role: "...", content_url: "..."})`;
  `image_url/2` reads only those two fields. The `content_url` paths are
  intentionally bogus — for the `*_with_logo` cases the real `<img>` tag
  will 404, but that's fine for layout verification, and the
  `:missing_artwork` / `:without_logo` variations exercise the
  more-interesting placeholder/fallback paths.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.Hero.hero/1
  def render_source, do: :function
  def layout, do: :one_column

  # The component is full-bleed (`aspect-[21/9]`, fills its container)
  # and the template wrapper paints a backdrop image behind it. Iframe
  # isolation keeps each variation's backdrop confined to its own
  # preview rather than bleeding across the storybook column.
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
            "suppressed. The logo image and tagline render over the (template-level) backdrop.",
        attributes: %{
          entity: entity_with_logo(),
          tagline: "A demonstrative tagline",
          available: true
        }
      },
      %Variation{
        id: :missing_artwork,
        description:
          "No backdrop, no poster (`images: []`) — the 21:9 frame fills with the " <>
            "`hero-film` placeholder icon. The title text still renders bottom-left " <>
            "since there's no logo either.",
        attributes: %{
          entity: entity_without_artwork(),
          tagline: "A demonstrative tagline",
          available: true
        }
      },
      %Variation{
        id: :without_logo,
        description:
          "Has a backdrop but no `\"logo\"` image — the placeholder is suppressed, " <>
            "but the title falls back to an `<h2>` heading instead of the logo `<img>`.",
        attributes: %{
          entity: entity_backdrop_only(),
          tagline: "A demonstrative tagline",
          available: true
        }
      },
      %Variation{
        id: :no_tagline,
        description:
          "`tagline: nil` — the tagline `<p>` is omitted. The logo and frame layout " <>
            "should remain otherwise identical to `:with_backdrop`.",
        attributes: %{
          entity: entity_with_logo(),
          tagline: nil,
          available: true
        }
      },
      %Variation{
        id: :with_actions,
        description:
          "Exercises the `actions` slot with a tracking-bell-style button — " <>
            "rendered absolutely positioned in the top-right of the 21:9 frame.",
        attributes: %{
          entity: entity_with_logo(),
          tagline: "A demonstrative tagline",
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
            "renders even when the entity has artwork, and the title falls back to " <>
            "the `<h2>` heading instead of the logo image.",
        attributes: %{
          entity: entity_with_logo(),
          tagline: "A demonstrative tagline",
          available: false
        }
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  defp entity_with_logo do
    %{
      name: "Sample Show",
      images: [
        %{role: "backdrop", content_url: "fixtures/hero-backdrop.jpg"},
        %{role: "logo", content_url: "fixtures/hero-logo.png"}
      ]
    }
  end

  defp entity_backdrop_only do
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
