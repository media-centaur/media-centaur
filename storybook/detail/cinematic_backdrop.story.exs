defmodule MediaCentaurWeb.Storybook.Detail.CinematicBackdrop do
  @moduledoc """
  The detail modal's cinematic page structure — a backdrop that fades into
  `base-100` plus a left-weighted vertical scrim — shared by the owned
  detail panel (`ModalShell`) and the acquisition plan modal's movie
  preview. The caller supplies a `position: relative` scroll container;
  the template below stands in for it.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.CinematicBackdrop.cinematic_backdrop/1
  def render_source, do: :function

  # The component renders a fragment that expects a `relative`, height-bearing
  # positioning container (the real caller's scroll surface). Stand one in.
  def template do
    """
    <div class="relative h-[26rem] overflow-hidden rounded-xl" style="background-color: var(--color-base-100)">
      <.psb-variation/>
    </div>
    """
  end

  @backdrop "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='9'%3E%3Crect width='16' height='9' fill='%234b5563'/%3E%3C/svg%3E"

  def variations do
    [
      %Variation{
        id: :with_backdrop,
        description:
          "Backdrop present — the image fades into the panel background and the atmosphere " <>
            "scrim weights the lower-left so title text stays legible.",
        attributes: %{backdrop_url: @backdrop},
        slots: [content_slot()]
      },
      %Variation{
        id: :early_fade,
        description:
          "Work-surface variant (`early_fade`) — the backdrop resolves into the panel " <>
            "background high up, so pickers and boards read over solid ground while the " <>
            "header band keeps the identity. The pursuit modal and the plan modal's " <>
            "non-hero stages wear this.",
        attributes: %{backdrop_url: @backdrop, early_fade: true},
        slots: [content_slot()]
      },
      %Variation{
        id: :atmosphere_only,
        description:
          "No backdrop URL — just the atmosphere scrim over the content (the state a title " <>
            "with no artwork falls back to).",
        attributes: %{backdrop_url: nil},
        slots: [content_slot()]
      }
    ]
  end

  defp content_slot do
    """
    <div class="aspect-[21/9] relative">
      <div class="absolute bottom-4 left-6 right-6">
        <h2 class="text-2xl font-bold text-white text-on-image-lg">Sample Title</h2>
        <p class="italic text-sm text-white/85 text-on-image">A representative tagline.</p>
      </div>
    </div>
    <div class="px-6 pb-6 text-sm text-base-content/70">
      Body content flows over the constant-dim region of the atmosphere.
    </div>
    """
  end
end
