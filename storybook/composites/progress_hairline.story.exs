defmodule MediaCentaurWeb.Storybook.Composites.ProgressHairline do
  @moduledoc """
  The cinematic hero's progress hairline (UIDR-024) — the single progress
  gauge of the cinematic modals, rendered flush on the hero window's
  bottom edge by every tenant that shows subject progress.

  The variations sweep the fraction range: the bare track at `0.0`
  (unstarted — deliberately visible so states share geometry), a sliver,
  the mid-watch happy path, near-complete (the leading-edge glow must not
  overflow), and the full track at `1.0`.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ProgressHairline.progress_hairline/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl py-4">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :unstarted,
        description:
          "Fraction 0.0 — the bare track. Rendered on purpose (not hidden) so " <>
            "unstarted, mid-watch, and watched states occupy identical geometry.",
        attributes: %{fraction: 0.0, label: "Movie progress"}
      },
      %Variation{
        id: :sliver,
        description: "A few minutes in (4%) — the fill and its leading-edge glow stay visible.",
        attributes: %{fraction: 0.04, label: "Movie progress"}
      },
      %Variation{
        id: :mid_watch,
        description: "The mid-watch happy path (75%).",
        attributes: %{fraction: 0.75, label: "Movie progress"}
      },
      %Variation{
        id: :near_complete,
        description: "Near the end (97%) — pins that the leading edge never overflows the track.",
        attributes: %{fraction: 0.97, label: "Series progress"}
      },
      %Variation{
        id: :complete,
        description: "Fully watched (1.0) — the fill spans the track; no leading-edge burn.",
        attributes: %{fraction: 1.0, label: "Series progress"}
      }
    ]
  end
end
