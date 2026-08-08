defmodule MediaCentaurWeb.Storybook.Detail.WatchedToggle do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.PlayableRow.watched_toggle/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :states,
        description:
          "The three row states. Unwatched shows the runtime beside an empty " <>
            "circle; current shows the remaining time in info blue; watched " <>
            "drops the duration and fills the circle. Hover the circle for the " <>
            "check preview.",
        variations: [
          %Variation{
            id: :unwatched,
            attributes: %{
              event: "toggle_watched",
              state: :unwatched,
              duration_seconds: 2640
            }
          },
          %Variation{
            id: :current,
            attributes: %{
              event: "toggle_watched",
              state: :current,
              progress: %{position_seconds: 900.0, duration_seconds: 2640.0},
              duration_seconds: 2640
            }
          },
          %Variation{
            id: :watched,
            attributes: %{
              event: "toggle_watched",
              state: :watched,
              duration_seconds: 2640
            }
          }
        ]
      },
      %Variation{
        id: :no_duration,
        description: "Extras carry no runtime — the toggle renders the bare circle.",
        attributes: %{event: "toggle_extra_watched", state: :unwatched}
      }
    ]
  end
end
