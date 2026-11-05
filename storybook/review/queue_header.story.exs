defmodule MediaCentaurWeb.Storybook.Review.QueueHeader do
  @moduledoc "The column names over Review's bulk list; its tick ticks every row shown."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewQueue.queue_header/1
  def render_source, do: :function
  def layout, do: :one_column
  def template, do: ~s|<div class="w-[1200px] glass-surface rounded-lg p-2"><.psb-variation/></div>|

  def variations do
    [
      %VariationGroup{
        id: :states,
        description: "None, some and every row shown ticked",
        variations:
          for(
            state <- [:unchecked, :indeterminate, :checked],
            do: %Variation{id: state, attributes: %{state: state}}
          )
      },
      %Variation{
        id: :importing,
        description: "The Importing view: no tick",
        attributes: %{state: :unchecked, selectable: false}
      }
    ]
  end
end
