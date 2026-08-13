defmodule MediaCentaurWeb.Storybook.Detail.Lockup do
  @moduledoc """
  The identity lockup — logo PNG (or logotype text fallback) plus
  optional tagline, shadowed for legibility over imagery (UIDR-011).
  One representation, two seatings: `title_layer/1` positions it
  bottom-left inside its 21:9 frame (plan modal), and the detail
  panel's orientation block seats it in normal flow so it pins with
  the block on scroll.

  The logo `<img>` fixture path is intentionally bogus — the 404 falls
  through visually; `:text_fallback` and `:with_tagline` exercise the
  interesting text paths.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.TitleLayer.lockup/1
  def render_source, do: :function

  # Shadow recipes only read over imagery — stand a dark panel in.
  def template do
    """
    <div class="rounded-lg bg-base-100 p-6">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :text_fallback,
        description: "No logo URL — the title renders as the `<h2>` logotype fallback.",
        attributes: %{title: "Quiet Sample Series"}
      },
      %Variation{
        id: :with_tagline,
        description: "Tagline present — italic line under the title.",
        attributes: %{title: "Quiet Sample Series", tagline: "Every afternoon, a different door."}
      },
      %Variation{
        id: :with_logo,
        description:
          "Logo URL present — the `<img>` replaces the logotype (fixture path 404s " <>
            "in storybook; layout only).",
        attributes: %{
          title: "Quiet Sample Series",
          logo_url: "fixtures/sample-logo.png",
          tagline: "Every afternoon, a different door."
        }
      }
    ]
  end
end
