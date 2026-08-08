defmodule MediaCentaurWeb.Storybook.Detail.ProgressUnderline do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.PlayableRow.progress_underline/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %VariationGroup{
        id: :fill,
        description:
          "Thin in-progress underline below a `:current` row — the fill width " <>
            "tracks playback position. Callers guard on state and pass the " <>
            "left margin that aligns the track with their text column.",
        variations: [
          %Variation{
            id: :early,
            attributes: %{progress: %{position_seconds: 660.0, duration_seconds: 2640.0}}
          },
          %Variation{
            id: :late,
            attributes: %{progress: %{position_seconds: 2100.0, duration_seconds: 2640.0}}
          },
          %Variation{
            id: :indented,
            attributes: %{
              progress: %{position_seconds: 1320.0, duration_seconds: 2640.0},
              class: "ml-9"
            }
          }
        ]
      }
    ]
  end
end
