defmodule MediaCentaurWeb.Storybook.Review.ReviewListItem do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewListItem.review_list_item/1
  def render_source, do: :function

  @list ~s|<div class="w-[340px] glass-surface rounded-lg p-2"><.psb-variation/></div>|

  def variations do
    [
      %Variation{
        id: :idle,
        description: "A row the detail pane does not show.",
        template: @list,
        attributes: %{id: "review-list-item-idle"},
        slots: [
          ~s|<div class="flex-1 min-w-0"><div class="text-sm font-medium truncate">Sample Show</div><div class="text-xs text-base-content/55">2 files to map</div></div>|
        ]
      },
      %Variation{
        id: :selected,
        description: "The row the detail pane shows: tinted, `aria-current`.",
        template: @list,
        attributes: %{id: "review-list-item-selected", selected: true},
        slots: [
          ~s|<div class="flex-1 min-w-0"><div class="text-sm font-medium truncate">Movie A</div><div class="text-xs text-base-content/55">2010 · Movie</div></div><span class="text-xs text-error shrink-0">No results</span>|
        ]
      }
    ]
  end
end
