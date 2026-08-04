defmodule MediaCentaurWeb.Storybook.Detail.OrientationMarquee do
  @moduledoc """
  Orientation marquee — the TV detail hero's "where am I" block
  (2026-08-04 orientation design). Variations pin the four states of
  `MediaCentaurWeb.ViewModel.Orientation`:

    * `:in_progress` — overline "Up next", large `S4 · E10`, full
      subline with runtime, season counts, and series percent.
    * `:unstarted` — overline "Start here", sizes instead of progress.
    * `:single_season` — subline drops the series clause (the season
      is the series).
    * `:complete` — no episode marquee; overline "Series complete" and
      the watched total.

  Fixtures are literal `%Orientation{}` structs — the component's
  entire contract. The episode title is never rendered here by design
  (spoiler-free is position-only).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.ViewModel.Orientation

  def function, do: &MediaCentaurWeb.Components.Detail.OrientationMarquee.orientation_marquee/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :in_progress,
        description: "Mid-series — the common case.",
        attributes: %{
          orientation: %Orientation{
            state: :in_progress,
            next: %{season_number: 4, episode_number: 10, runtime_seconds: 1260},
            season: %{number: 4, watched: 9, total: 22},
            series: %{watched: 67, total: 138, percent: 49, season_count: 7}
          }
        }
      },
      %Variation{
        id: :unstarted,
        description: "Nothing watched yet — sizes, not progress.",
        attributes: %{
          orientation: %Orientation{
            state: :unstarted,
            next: %{season_number: 1, episode_number: 1, runtime_seconds: 1320},
            season: %{number: 1, watched: 0, total: 21},
            series: %{watched: 0, total: 138, percent: 0, season_count: 7}
          }
        }
      },
      %Variation{
        id: :single_season,
        description: "One-season series — the series clause is dropped.",
        attributes: %{
          orientation: %Orientation{
            state: :in_progress,
            next: %{season_number: 1, episode_number: 10, runtime_seconds: 1260},
            season: %{number: 1, watched: 9, total: 22},
            series: %{watched: 9, total: 22, percent: 41, season_count: 1}
          }
        }
      },
      %Variation{
        id: :complete,
        description: "Everything watched — no episode marquee.",
        attributes: %{
          orientation: %Orientation{
            state: :complete,
            next: nil,
            season: nil,
            series: %{watched: 138, total: 138, percent: 100, season_count: 7}
          }
        }
      }
    ]
  end
end
