defmodule MediaCentaurWeb.Storybook.ReleaseTracking.ReleaseDates do
  @moduledoc """
  What the app knows about a title's upcoming dates — the readout beside
  the tracking switches on both title surfaces (UIDR-035, spec
  2026-09-14 iteration 2). A movie's three rows from the live release
  window or the calendar; a series' next dated episodes; the one word
  beside the row the app is acting on.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaur.TMDB.ReleaseWindow

  def function, do: &MediaCentaurWeb.Components.ReleaseTracking.ReleaseDates.release_dates/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-sm p-4">
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

  defp movie_event(type, air_date, status, extra \\ %{}) do
    struct!(
      %Event{
        id: "movie-#{type}",
        item_id: "sample-movie",
        item_name: "Sample Movie",
        media_type: :movie,
        kind: :movie,
        release_type: type,
        air_date: air_date,
        status: status
      },
      extra
    )
  end

  def variations do
    [
      %Variation{
        id: :movie_in_theaters,
        description:
          "A movie in theaters with no home date yet, from the live release window alone — " <>
            "the readout works before the title is even listed.",
        attributes: %{
          media_type: :movie,
          release_window: %ReleaseWindow{stage: :theatrical, theatrical: ~D[2026-07-24]},
          today: @today
        }
      },
      %Variation{
        id: :movie_armed,
        description:
          "A tracked movie at Grab: the digital date is the calendar's and will download; " <>
            "the disc date is TMDB's from the window.",
        attributes: %{
          media_type: :movie,
          release_window: %ReleaseWindow{
            stage: :theatrical,
            theatrical: ~D[2026-07-24],
            digital: ~D[2026-09-15],
            physical: ~D[2026-11-03]
          },
          timeline: [
            movie_event("digital", ~D[2026-09-15], :armed),
            movie_event("physical", ~D[2026-11-03], :armed_fallback)
          ],
          today: @today
        }
      },
      %Variation{
        id: :movie_downloading,
        description: "The digital release dropped and is being grabbed: a link to the pursuit.",
        attributes: %{
          media_type: :movie,
          timeline: [
            movie_event("theatrical", ~D[2026-05-01], :theatrical_info),
            movie_event("digital", ~D[2026-08-01], :under_pursuit, %{pursuit_id: "pursuit-1"})
          ],
          today: @today
        }
      },
      %Variation{
        id: :weekly_show,
        description:
          "A weekly show: tonight's episode will download, next week's is dated, the landed " <>
            "one is left out.",
        attributes: %{
          media_type: :tv_series,
          timeline: [
            episode("s02e05", 2, 5, @today, :armed, %{title: "The Vanishing Reel"}),
            episode("s02e06", 2, 6, ~D[2026-08-11], :upcoming),
            episode("s02e04", 2, 4, ~D[2026-07-27], :in_library)
          ],
          today: @today
        }
      },
      %Variation{
        id: :show_nothing_dated,
        description: "A tracked show between seasons: TMDB has posted no air dates.",
        attributes: %{media_type: :tv_series, timeline: [], today: @today}
      }
    ]
  end
end
