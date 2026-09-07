defmodule MediaCentaurWeb.Storybook.ReleaseTracking.ReleaseTimeline do
  @moduledoc """
  A tracked title's release timeline — the shared component both title
  surfaces mount (UIDR-035). The featured next release answers "what's
  next" first; the dated list follows, landed entries keeping their
  success label; nothing scheduled states the absence plainly.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  def function, do: &MediaCentaurWeb.Components.ReleaseTracking.ReleaseTimeline.release_timeline/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl p-4">
      <.psb-variation/>
    </div>
    """
  end

  @today ~D[2026-08-03]

  defp episode(id, season, episode, air_date, status, extra \\ %{}) do
    struct!(
      %Event{
        id: id,
        item_id: "sample-show",
        item_name: "Sample Show",
        media_type: :tv_series,
        kind: :episode,
        season_number: season,
        episode_number: episode,
        air_date: air_date,
        status: status
      },
      extra
    )
  end

  defp weekly_show do
    [
      episode("s02e05", 2, 5, @today, :armed, %{title: "The Vanishing Reel"}),
      episode("s02e06", 2, 6, ~D[2026-08-11], :upcoming),
      episode("s02e04", 2, 4, ~D[2026-07-27], :in_library)
    ]
  end

  def variations do
    [
      %Variation{
        id: :weekly_show,
        description:
          "A weekly show with releases ahead: tonight's episode is the featured next release " <>
            "(Will grab), then the full list — the landed entry keeps its success label.",
        attributes: %{timeline: weekly_show(), today: @today}
      },
      %Variation{
        id: :under_pursuit,
        description:
          "A release being grabbed right now: the status is a deep-link to the pursuit on Incoming.",
        attributes: %{
          timeline: [
            episode("s02e05", 2, 5, @today, :under_pursuit, %{pursuit_id: "pursuit-1"}),
            episode("s02e06", 2, 6, ~D[2026-08-11], :upcoming)
          ],
          today: @today
        }
      },
      %Variation{
        id: :movie_dates,
        description:
          "A film's release types: the theatrical date informs (we grab the digital release), " <>
            "the digital date is armed, the physical date is the neutral fallback.",
        attributes: %{
          timeline: [
            %Event{
              id: "theatrical",
              item_id: "sample-movie",
              item_name: "Sample Movie",
              media_type: :movie,
              kind: :movie,
              release_type: "theatrical",
              air_date: ~D[2026-08-14],
              status: :theatrical_info
            },
            %Event{
              id: "digital",
              item_id: "sample-movie",
              item_name: "Sample Movie",
              media_type: :movie,
              kind: :movie,
              release_type: "digital",
              air_date: ~D[2026-10-02],
              status: :armed
            },
            %Event{
              id: "physical",
              item_id: "sample-movie",
              item_name: "Sample Movie",
              media_type: :movie,
              kind: :movie,
              release_type: "physical",
              air_date: ~D[2026-11-20],
              status: :armed_fallback
            }
          ],
          today: @today
        }
      },
      %Variation{
        id: :nothing_scheduled,
        description:
          "A tracked title with no dated release: the featured slot states the absence " <>
            "instead of rendering empty, and there is no list.",
        attributes: %{timeline: [], today: @today}
      },
      %Variation{
        id: :undated_entry,
        description: "An undated release rides at the end of the list with no day column.",
        attributes: %{
          timeline: [
            episode("s02e06", 2, 6, ~D[2026-08-11], :upcoming),
            episode("s03e01", 3, 1, nil, :unscheduled)
          ],
          today: @today
        }
      }
    ]
  end
end
