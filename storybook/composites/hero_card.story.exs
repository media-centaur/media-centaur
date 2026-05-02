defmodule MediaCentarrWeb.Storybook.Composites.HeroCard do
  @moduledoc """
  Full-bleed hero card for the Home page.

  The component itself only renders the foreground (logo/title, meta line,
  overview, action buttons). The backdrop image and side-dim scrim are
  provided by the parent page (see `HomeLive`'s `.page-backdrop` and
  `.page-side-dim` divs). The story's template recreates that context so
  the previews show the component as it actually appears.

  Variations are minimally-shaped `HeroCard.Item` structs — no factories,
  generic placeholder titles only.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Components.HeroCard

  def function, do: &HeroCard.hero_card/1
  def render_source, do: :function
  def layout, do: :one_column

  # The hero is sized by viewport width (`width: 100vw * 9/16`, min 400px),
  # so each variation needs its own full-width frame — without an iframe
  # they collapse into the storybook content column. Iframes also isolate
  # the page-level `.page-backdrop`/`.page-side-dim` scrims so they only
  # cover their own variation.
  def container, do: {:iframe, style: "min-height: 480px; width: 100%;"}

  def template do
    """
    <div class="relative bg-base-100 min-h-[460px] overflow-hidden">
      <div class="page-backdrop" aria-hidden="true">
        <img src="https://placehold.co/1920x1080/1a1a1a/333333?text=Backdrop+placeholder" alt="" />
      </div>
      <div class="page-side-dim" aria-hidden="true"></div>
      <div class="relative z-[1]">
        <.psb-variation/>
      </div>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :with_artwork,
        description:
          "Happy path — title text, year, genre, runtime meta line, overview paragraph, " <>
            "and Play / More info actions over the page-level backdrop.",
        attributes: %{item: sample_item()}
      },
      %Variation{
        id: :missing_artwork,
        description:
          "No `logo_url` — the component falls back to the large title typography " <>
            "(`text-7xl` heading) instead of the brand logo image.",
        attributes: %{item: %{sample_item() | logo_url: nil}}
      },
      %Variation{
        id: :long_title,
        description:
          "Long title — verifies that the title heading wraps cleanly without the " <>
            "meta line or buttons being pushed off the visible hero area.",
        attributes: %{
          item: %{
            sample_item()
            | logo_url: nil,
              name:
                "An Extraordinarily Long Placeholder Title That Wraps Across Multiple Lines To Verify Layout"
          }
        }
      },
      %Variation{
        id: :with_metadata_badges,
        description:
          "All meta fields present — year, genre label, and runtime separated by " <>
            "middle-dot dividers. The component hides each absent field, so this is " <>
            "the densest meta line the component will render.",
        attributes: %{
          item: %{
            sample_item()
            | logo_url: nil,
              year: "2024",
              genre_label: "Drama, Adventure, Sci-Fi",
              runtime: "2h 18m"
          }
        }
      },
      %Variation{
        id: :focused,
        description:
          "Action buttons are the focusable elements. Focus rings only render when " <>
            "the document is in keyboard input mode (`[data-input=\"keyboard\"]`); " <>
            "the storybook iframe stays in mouse mode, so this preview shows resting " <>
            "button styling rather than a focus ring.",
        attributes: %{item: sample_item()}
      }
    ]
  end

  # --- Fixtures ----------------------------------------------------------

  defp sample_item do
    %HeroCard.Item{
      id: "hero-fixture-1",
      entity_id: "hero-fixture-1",
      name: "Sample Movie",
      year: "2024",
      runtime: "2h 8m",
      genre_label: "Drama, Adventure",
      overview:
        "A short placeholder overview used for the storybook. It has enough text " <>
          "to exercise the five-line clamp without spilling past the hero's " <>
          "vertical bounds, and it gives the surrounding meta line and action " <>
          "buttons a realistic context to lay out against.",
      backdrop_url: nil,
      logo_url: nil
    }
  end
end
