defmodule MediaCentaurWeb.Storybook.CoreComponents.CheckboxMark do
  @moduledoc "The checkbox's square alone, for a row that is itself the control — Review's bulk list."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Checkbox.checkbox_mark/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :states,
        description: "Ticked, partly ticked, empty, disabled",
        variations:
          for state <- [:checked, :indeterminate, :unchecked, :disabled] do
            %Variation{id: state, attributes: %{state: state}}
          end
      }
    ]
  end
end
