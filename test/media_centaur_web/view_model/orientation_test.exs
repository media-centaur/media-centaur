defmodule MediaCentaurWeb.ViewModel.OrientationTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory, only: [build_episode: 1, build_movie: 1]

  alias MediaCentaurWeb.ViewModel.EpisodeListItem
  alias MediaCentaurWeb.ViewModel.MovieListItem
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

  # Collection fixture: `watched` movies watched out of `total`, with the
  # movie after the watched prefix marked as the resume target when
  # `resume_target: true` is given.
  defp collection_items(watched, total, opts \\ []) do
    resume_target = Keyword.get(opts, :resume_target, false)

    for ordinal <- 1..total do
      state = if ordinal <= watched, do: :watched, else: :unwatched

      %MovieListItem.Library{
        movie: build_movie(%{name: "Movie #{ordinal}"}),
        state: state,
        is_resume_target: resume_target && ordinal == watched + 1
      }
    end
  end

  defp upcoming_part(part_tmdb_id) do
    %MovieListItem.Upcoming{part_tmdb_id: part_tmdb_id, sub_status: :unaired}
  end

  describe "for_series/2 mid-series" do
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

      orientation = Orientation.for_series(seasons, resume_hint(4, 10))

      assert orientation.state == :in_progress
      assert orientation.next == %{season_number: 4, episode_number: 10}
      assert orientation.season == %{number: 4, watched: 9, total: 22}
      assert orientation.series == %{watched: 67, total: 138, percent: 49}
    end

    test "future seasons are excluded from series totals" do
      seasons = [library_season(1, 3, 10, resume_target: true), future_season(2)]

      orientation = Orientation.for_series(seasons, resume_hint(1, 4))

      assert orientation.series == %{watched: 3, total: 10, percent: 30}
    end

    test "without a resume hint, next falls back to the first unwatched library item" do
      seasons = [library_season(1, 10, 10), library_season(2, 2, 8)]

      orientation = Orientation.for_series(seasons, nil)

      assert orientation.next.season_number == 2
      assert orientation.next.episode_number == 3
      assert orientation.season == %{number: 2, watched: 2, total: 8}
    end
  end

  describe "for_series/2 edge states" do
    test "unstarted series" do
      seasons = [library_season(1, 0, 21), library_season(2, 0, 15)]

      orientation = Orientation.for_series(seasons, resume_hint(1, 1))

      assert orientation.state == :unstarted
      assert orientation.next == %{season_number: 1, episode_number: 1}
      assert orientation.season == %{number: 1, watched: 0, total: 21}
      assert orientation.series == %{watched: 0, total: 36, percent: 0}
    end

    test "fully watched series" do
      seasons = [library_season(1, 21, 21), library_season(2, 15, 15)]

      orientation = Orientation.for_series(seasons, nil)

      assert orientation.state == :complete
      assert orientation.next == nil
      assert orientation.season == nil
      assert orientation.series.percent == 100
    end

    test "no library seasons at all" do
      orientation = Orientation.for_series([future_season(1)], nil)

      assert orientation.state == :unstarted
      assert orientation.next == nil
      assert orientation.season == nil
      assert orientation.series == %{watched: 0, total: 0, percent: 0}
    end
  end

  describe "for_series/2 fraction" do
    test "fraction of the current season watched" do
      seasons = [library_season(1, 9, 22, resume_target: true)]

      orientation = Orientation.for_series(seasons, resume_hint(1, 10))

      assert_in_delta orientation.fraction, 9 / 22, 0.0001
    end

    test "full for a completed series — the hairline reads finished, not empty" do
      orientation = Orientation.for_series([library_season(1, 5, 5)], nil)

      assert orientation.fraction == 1.0
    end
  end

  describe "initial_expanded_seasons/1" do
    test "mid-series opens the season holding the next episode" do
      seasons = [
        library_season(1, 21, 21),
        library_season(2, 9, 22, resume_target: true),
        library_season(3, 0, 13)
      ]

      orientation = Orientation.for_series(seasons, resume_hint(2, 10))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new([2])
    end

    test "unstarted series opens season one" do
      seasons = [library_season(1, 0, 21), library_season(2, 0, 15)]

      orientation = Orientation.for_series(seasons, resume_hint(1, 1))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new([1])
    end

    test "completed series opens nothing — the rows are a rewatch index" do
      orientation = Orientation.for_series([library_season(1, 5, 5)], nil)

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new()
    end

    test "no current season opens nothing" do
      orientation = Orientation.for_series([future_season(1)], nil)

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new()
    end
  end

  describe "for_series/2 autoscroll" do
    test "mid-series scrolls to the next episode" do
      seasons = [library_season(1, 21, 21), library_season(2, 9, 22, resume_target: true)]

      assert Orientation.for_series(seasons, resume_hint(2, 10)).autoscroll?
    end

    test "unstarted series stays on the hero" do
      refute Orientation.for_series([library_season(1, 0, 21)], resume_hint(1, 1)).autoscroll?
    end

    test "completed series stays on the hero" do
      refute Orientation.for_series([library_season(1, 5, 5)], nil).autoscroll?
    end
  end

  describe "for_collection/1" do
    test "mid-collection: fraction reads the whole collection, autoscroll returns to the resume row" do
      orientation = Orientation.for_collection(collection_items(1, 3, resume_target: true))

      assert orientation.state == :in_progress
      assert orientation.season == nil
      assert orientation.series == %{watched: 1, total: 3, percent: 33}
      assert_in_delta orientation.fraction, 1 / 3, 0.0001
      assert orientation.autoscroll?
    end

    test "unstarted collection stays on the hero — a first movie, not a next one" do
      orientation = Orientation.for_collection(collection_items(0, 3, resume_target: true))

      assert orientation.state == :unstarted
      assert orientation.fraction == 0.0
      refute orientation.autoscroll?
    end

    test "completed collection reads finished, not empty" do
      orientation = Orientation.for_collection(collection_items(3, 3))

      assert orientation.state == :complete
      assert orientation.fraction == 1.0
      refute orientation.autoscroll?
    end

    test "mid-collection with no resume row to return to does not autoscroll" do
      orientation = Orientation.for_collection(collection_items(1, 3))

      assert orientation.state == :in_progress
      refute orientation.autoscroll?
    end

    test "upcoming parts are excluded from all counts" do
      items = collection_items(1, 2, resume_target: true) ++ [upcoming_part(900_001)]

      orientation = Orientation.for_collection(items)

      assert orientation.series == %{watched: 1, total: 2, percent: 50}
      assert_in_delta orientation.fraction, 0.5, 0.0001
    end

    test "collection accordion projection opens nothing — there are no seasons" do
      orientation = Orientation.for_collection(collection_items(1, 3, resume_target: true))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new()
    end
  end

  # subline/marquee/overline were removed 2026-08-05: the up-next block
  # duplicated the Play button's own label, so the hairline is the only
  # orientation element the hero renders.
end
