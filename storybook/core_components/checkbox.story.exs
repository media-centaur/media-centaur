defmodule MediaCentaurWeb.Storybook.CoreComponents.Checkbox do
  @moduledoc "The house checkbox as its own control — the plan modal's seasons and episodes."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Checkbox.checkbox/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :states,
        description: "Ticked, partly ticked (a block with some rows ticked), empty, disabled",
        variations:
          for state <- [:checked, :indeterminate, :unchecked, :disabled] do
            %Variation{id: state, attributes: %{state: state}}
          end
      },
      %VariationGroup{
        id: :small,
        description: "16px, for a nested row",
        variations:
          for state <- [:checked, :unchecked] do
            %Variation{id: state, attributes: %{state: state, small: true}}
          end
      }
    ]
  end
end
