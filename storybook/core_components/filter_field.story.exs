defmodule MediaCentaurWeb.Storybook.CoreComponents.FilterField do
  @moduledoc "The house filter field — Library's toolbar, the cast panel, Review's bulk list."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.FilterField.filter_field/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :idle,
        description: "Empty and unfocused: the icon pill; focus widens it",
        attributes: %{name: "q", placeholder: "Filter by name…", aria_label: "Filter by name"}
      },
      %Variation{
        id: :search_type,
        description: "A search input (the cast panel's), tinted",
        attributes: %{
          type: "search",
          name: "cast_filter",
          placeholder: "Filter cast",
          aria_label: "Filter cast members",
          class: "w-64 bg-base-content/5"
        }
      },
      %Variation{
        id: :with_text,
        description: "Holding text, with the clear button",
        attributes: %{
          name: "q",
          value: "sample",
          placeholder: "Filter by name…",
          aria_label: "Filter by name",
          clear_event: "clear_filter",
          class: "w-72"
        }
      }
    ]
  end
end
