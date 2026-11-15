defmodule MediaCentaurWeb.Storybook.Detail.WatchedToggle do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.PlayableRow.watched_toggle/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :states,
        description:
          "An item with neither fact shows the runtime beside an empty circle; " <>
            "a viewing in flight shows the remaining time in info blue; the " <>
            "watched mark fills the circle and, with no viewing, drops the " <>
            "duration. Hover the circle for the check preview.",
        variations: [
          %Variation{
            id: :unwatched,
            attributes: %{
              event: "toggle_watched",
              duration_seconds: 2640
            }
          },
          %Variation{
            id: :viewing,
            attributes: %{
              event: "toggle_watched",
              progress: %{position_seconds: 900.0, duration_seconds: 2640.0},
              duration_seconds: 2640
            }
          },
          %Variation{
            id: :watched,
            attributes: %{
              event: "toggle_watched",
              progress: %{completed: true, position_seconds: 0.0, duration_seconds: 2640.0},
              duration_seconds: 2640
            }
          }
        ]
      },
      %Variation{
        id: :watched_being_replayed,
        description:
          "A watched item being replayed: the mark is set and a viewing is in " <>
            "flight. The circle stays filled, the remaining time shows beside " <>
            "it, and the control offers Mark unwatched.",
        attributes: %{
          event: "toggle_watched",
          progress: %{completed: true, position_seconds: 900.0, duration_seconds: 2640.0},
          duration_seconds: 2640
        }
      },
      %Variation{
        id: :no_duration,
        description: "Extras carry no runtime — the toggle renders the bare circle.",
        attributes: %{event: "toggle_extra_watched"}
      },
      %Variation{
        id: :duration_suppressed,
        description:
          "`show_duration: false` — the bare circle even mid-watch. The " <>
            "collection modal's play line uses this: the PlayCard's progress " <>
            "row directly above already carries the remaining copy (UIDR-023).",
        attributes: %{
          event: "toggle_watched",
          progress: %{position_seconds: 900.0, duration_seconds: 2640.0},
          duration_seconds: 2640,
          show_duration: false
        }
      }
    ]
  end
end
