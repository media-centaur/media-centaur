defmodule MediaCentaurWeb.Storybook.Review.QueueDivider do
  @moduledoc "Where the parsed title changes in Review's bulk list; pressing it ticks the block."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ReviewQueue.queue_divider/1
  def render_source, do: :function
  def layout, do: :one_column
  def template, do: ~s|<div class="w-[1200px] glass-surface rounded-lg p-2"><.psb-variation/></div>|

  def variations do
    [
      %VariationGroup{
        id: :states,
        description: "None, some and all of the block ticked",
        variations:
          for state <- [:unchecked, :indeterminate, :checked] do
            %Variation{
              id: state,
              attributes: %{id: "divider-#{state}", label: "Sample Show Signed", count: 6, state: state}
            }
          end
      },
      %Variation{
        id: :with_year,
        description: "A name with a year is its own block",
        attributes: %{
          id: "divider-year",
          label: "Sample Show Signed (2005)",
          count: 1,
          state: :unchecked
        }
      },
      %Variation{
        id: :importing,
        description: "The Importing view: not a control",
        attributes: %{
          id: "divider-importing",
          label: "Sample Show",
          count: 2,
          state: :unchecked,
          selectable: false
        }
      }
    ]
  end
end
