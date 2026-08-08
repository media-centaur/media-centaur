defmodule MediaCentaurWeb.Storybook.Detail.CastFilterForm do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.CastPanel.cast_filter_form/1

  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :empty,
        description: "Resting — placeholder showing, as first rendered.",
        attributes: %{filter: ""}
      },
      %Variation{
        id: :active_query,
        description: "An active query, as typed by the user.",
        attributes: %{filter: "Sample Actor"}
      }
    ]
  end
end
