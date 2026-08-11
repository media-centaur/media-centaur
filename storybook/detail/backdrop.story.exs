defmodule MediaCentaurWeb.Storybook.Detail.Backdrop do
  @moduledoc """
  The cinematic backdrop image layer — the full-width image that fades
  into `base-100`. `CinematicShell` seats it panel-fixed behind the
  scroll surface; the pinned orientation block replicates the same URL.
  The caller supplies a `position: relative` container; the template
  below stands in for it.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.CinematicBackdrop.backdrop/1
  def render_source, do: :function

  # The component renders an absolutely-positioned layer that expects a
  # `relative`, height-bearing positioning container (the real caller's
  # modal panel). Stand one in.
  def template do
    """
    <div class="relative h-[22rem] overflow-hidden rounded-xl" style="background-color: var(--color-base-100)">
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
          "Backdrop present — the image fades into the panel background so content below " <>
            "reads over solid ground.",
        attributes: %{backdrop_url: @backdrop}
      },
      %Variation{
        id: :absent,
        description:
          "No backdrop URL — the layer renders nothing at all; the frame shows its quiet " <>
            "placeholder in the hero window instead.",
        attributes: %{backdrop_url: nil}
      }
    ]
  end
end
