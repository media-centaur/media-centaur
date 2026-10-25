defmodule MediaCentaurWeb.Storybook.Composites.ScrollRow do
  @moduledoc """
  A scroll row: the `.row-scroll` track with its two edge arrows. The arrows
  reveal on hover (move the pointer over a variation to see them), and the
  track's edge state decides which: `data-at-start` drops the left arrow,
  `data-at-end` the right, both drop both. In the app the `ScrollRow` hook
  writes those from the track's geometry; the storybook loads no hooks, so
  each variation sets them as a fixture — the state matrix, not the motion.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.ScrollRow

  def function, do: &ScrollRow.scroll_row/1
  def render_source, do: :function
  def layout, do: :one_column

  # The sandbox is a column flex that centres its items, which would size
  # the row to its track's full content width and run both ends off-screen.
  # A full-width block wrapper gives the row the sandbox's width, as a
  # page's column does in the app.
  def template do
    """
    <div class="w-full" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :at_start,
        description: "Scroll 0 — only the right arrow shows under hover",
        attributes: %{id: "scroll-row-at-start", variant: :poster, "data-at-start": true},
        slots: [cards(12)]
      },
      %Variation{
        id: :mid_row,
        description: "Mid-row — both arrows show under hover",
        attributes: %{id: "scroll-row-mid-row", variant: :poster},
        slots: [cards(12)]
      },
      %Variation{
        id: :at_end,
        description: "At the end — only the left arrow shows under hover",
        attributes: %{id: "scroll-row-at-end", variant: :poster, "data-at-end": true},
        slots: [cards(12)]
      },
      %Variation{
        id: :fits,
        description: "A row that fits carries both edge attributes and shows no arrows",
        attributes: %{
          id: "scroll-row-fits",
          variant: :poster,
          "data-at-start": true,
          "data-at-end": true
        },
        slots: [cards(2)]
      },
      %Variation{
        id: :backdrop_lg,
        description: "The Continue Watching variant: 16:9 cards on the wider gap",
        attributes: %{id: "scroll-row-backdrop-lg", variant: :backdrop_lg},
        slots: [backdrop_cards(8)]
      },
      %Variation{
        id: :backdrop_sm,
        description: "The collection rail variant: small 16:9 tiles on the tighter gap",
        attributes: %{id: "scroll-row-backdrop-sm", variant: :backdrop_sm},
        slots: [backdrop_cards(14)]
      }
    ]
  end

  defp cards(count) do
    Enum.map_join(1..count, "\n", fn n ->
      ~s|<div class="aspect-[2/3] rounded glass-inset grid place-items-center text-sm text-base-content/55" data-row-item>#{n}</div>|
    end)
  end

  defp backdrop_cards(count) do
    Enum.map_join(1..count, "\n", fn n ->
      ~s|<div class="aspect-[16/9] rounded-lg glass-inset grid place-items-center text-sm text-base-content/55" data-row-item>#{n}</div>|
    end)
  end
end
