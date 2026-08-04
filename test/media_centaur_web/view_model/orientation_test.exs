defmodule MediaCentaurWeb.ViewModel.OrientationTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory, only: [build_episode: 1]

  alias MediaCentaurWeb.ViewModel.EpisodeListItem
  alias MediaCentaurWeb.ViewModel.Orientation
  alias MediaCentaurWeb.ViewModel.SeasonView

  # Season fixture: `watched` episodes watched out of `total`, with the
  # episode after the watched prefix marked as the resume target when
  # `resume_target: true` is given.
  defp library_season(number, watched, total, opts \\ []) do
    runtime = Keyword.get(opts, :runtime_seconds, 1260)
    resume_target = Keyword.get(opts, :resume_target, false)

    items =
      for episode_number <- 1..total do
        state = if episode_number <= watched, do: :watched, else: :unwatched

        %EpisodeListItem.Library{
          episode: build_episode(%{episode_number: episode_number, duration_seconds: runtime}),
          season_number: number,
          state: state,
          is_resume_target: resume_target && episode_number == watched + 1
        }
      end

    %SeasonView{
      season_number: number,
      kind: :library,
      items: items,
      watched_count: watched,
      total_count: total
    }
  end

  defp future_season(number) do
    %SeasonView{season_number: number, kind: :future, items: []}
  end

  defp resume_hint(season_number, episode_number, action \\ "begin") do
    %{
      "action" => action,
      "seasonNumber" => season_number,
      "episodeNumber" => episode_number
    }
  end

  describe "build/2 mid-series" do
    test "identifies next episode, current season, and series totals" do
      seasons = [
        library_season(1, 21, 21),
        library_season(2, 15, 15),
        library_season(3, 22, 22),
        library_season(4, 9, 22, resume_target: true),
        library_season(5, 0, 23),
        library_season(6, 0, 22),
        library_season(7, 0, 13)
      ]

      orientation = Orientation.build(seasons, resume_hint(4, 10))

      assert orientation.state == :in_progress
      assert orientation.next == %{season_number: 4, episode_number: 10}
      assert orientation.season == %{number: 4, watched: 9, total: 22}
      assert orientation.series == %{watched: 67, total: 138, percent: 49, season_count: 7}
    end

    test "future seasons are excluded from series totals and season count" do
      seasons = [library_season(1, 3, 10, resume_target: true), future_season(2)]

      orientation = Orientation.build(seasons, resume_hint(1, 4))

      assert orientation.series == %{watched: 3, total: 10, percent: 30, season_count: 1}
    end

    test "without a resume hint, next falls back to the first unwatched library item" do
      seasons = [library_season(1, 10, 10), library_season(2, 2, 8)]

      orientation = Orientation.build(seasons, nil)

      assert orientation.next.season_number == 2
      assert orientation.next.episode_number == 3
      assert orientation.season == %{number: 2, watched: 2, total: 8}
    end
  end

  describe "build/2 edge states" do
    test "unstarted series" do
      seasons = [library_season(1, 0, 21), library_season(2, 0, 15)]

      orientation = Orientation.build(seasons, resume_hint(1, 1))

      assert orientation.state == :unstarted
      assert orientation.next == %{season_number: 1, episode_number: 1}
      assert orientation.season == %{number: 1, watched: 0, total: 21}
      assert orientation.series == %{watched: 0, total: 36, percent: 0, season_count: 2}
    end

    test "fully watched series" do
      seasons = [library_season(1, 21, 21), library_season(2, 15, 15)]

      orientation = Orientation.build(seasons, nil)

      assert orientation.state == :complete
      assert orientation.next == nil
      assert orientation.season == nil
      assert orientation.series.percent == 100
    end

    test "no library seasons at all" do
      orientation = Orientation.build([future_season(1)], nil)

      assert orientation.state == :unstarted
      assert orientation.next == nil
      assert orientation.season == nil
      assert orientation.series == %{watched: 0, total: 0, percent: 0, season_count: 0}
    end
  end

  describe "season_fraction/1" do
    test "fraction of the current season watched" do
      seasons = [library_season(1, 9, 22, resume_target: true)]

      orientation = Orientation.build(seasons, resume_hint(1, 10))

      assert_in_delta Orientation.season_fraction(orientation), 9 / 22, 0.0001
    end

    test "full for a completed series — the hairline reads finished, not empty" do
      orientation = Orientation.build([library_season(1, 5, 5)], nil)

      assert Orientation.season_fraction(orientation) == 1.0
    end
  end

  # subline/marquee/overline were removed 2026-08-05: the up-next block
  # duplicated the Play button's own label, so the hairline is the only
  # orientation element the hero renders.
end
