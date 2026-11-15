defmodule MediaCentaurWeb.ViewModel.OrientationTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_episode: 1, build_movie: 1]

  alias MediaCentaur.Library.TitleProgress
  alias MediaCentaurWeb.ViewModel.EpisodeRow
  alias MediaCentaurWeb.ViewModel.MovieRow
  alias MediaCentaurWeb.ViewModel.Orientation
  alias MediaCentaurWeb.ViewModel.SeasonView

  defp episode_id(season_number, episode_number), do: "s#{season_number}e#{episode_number}"

  # Season fixture: `watched` episodes carry a watched mark out of
  # `total`. The marks are what the season header counts; where the
  # profile stands comes from the title progress, not from them.
  defp library_season(number, watched, total) do
    items =
      for episode_number <- 1..total do
        %EpisodeRow.Library{
          episode:
            build_episode(%{id: episode_id(number, episode_number), episode_number: episode_number}),
          season_number: number,
          progress: if(episode_number <= watched, do: %{completed: true, position_seconds: 0.0}),
          is_resume_target: false
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

  defp next(item_id, offset \\ 0.0),
    do: %{item_id: item_id, offset_seconds: offset, duration_seconds: 1300.0}

  defp in_progress(item_id, before_next, total),
    do: %TitleProgress{state: :in_progress, next: next(item_id), before_next: before_next, total: total}

  defp unstarted(item_id, total),
    do: %TitleProgress{state: :unstarted, next: next(item_id), before_next: 0, total: total}

  defp complete(total), do: %TitleProgress{state: :complete, next: nil, before_next: total, total: total}

  defp movie_id(ordinal), do: "m#{ordinal}"

  defp collection_items(watched, total) do
    for ordinal <- 1..total do
      %MovieRow.Library{
        movie: build_movie(%{id: movie_id(ordinal), name: "Movie #{ordinal}"}),
        progress: if(ordinal <= watched, do: %{completed: true, position_seconds: 0.0}),
        is_resume_target: false
      }
    end
  end

  defp upcoming_part(part_tmdb_id) do
    %MovieRow.Upcoming{part_tmdb_id: part_tmdb_id, sub_status: :unaired}
  end

  describe "for_series/2 fraction" do
    test "the title progress measure over the whole series, not the current season" do
      seasons = [library_season(1, 10, 10), library_season(2, 9, 22), library_season(3, 0, 8)]

      orientation = Orientation.for_series(seasons, in_progress(episode_id(2, 10), 19, 40))

      assert orientation.fraction == 0.47
    end

    test "a rewatch reads in progress from the title progress, not from watched counts" do
      seasons = [library_season(1, 22, 22)]

      orientation = Orientation.for_series(seasons, in_progress(episode_id(1, 6), 5, 22))

      assert orientation.fraction == 0.22
      assert orientation.autoscroll?
      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new([1])
    end

    test "the viewing in flight of the next episode counts toward the measure" do
      seasons = [library_season(1, 1, 4)]

      progress = %TitleProgress{
        state: :in_progress,
        next: next(episode_id(1, 2), 650.0),
        before_next: 1,
        total: 4
      }

      assert Orientation.for_series(seasons, progress).fraction == 0.37
    end

    test "full for a complete series — the hairline reads finished, not empty" do
      assert Orientation.for_series([library_season(1, 5, 5)], complete(5)).fraction == 1.0
    end

    test "empty for an unstarted series and for one with no library episodes" do
      unstarted = Orientation.for_series([library_season(1, 0, 5)], unstarted(episode_id(1, 1), 5))
      assert unstarted.fraction == 0.0

      empty = %TitleProgress{state: :unstarted, next: nil, before_next: 0, total: 0}
      assert Orientation.for_series([future_season(1)], empty).fraction == 0.0
    end
  end

  describe "initial_expanded_seasons/1" do
    test "mid-series opens the season holding the next episode" do
      seasons = [library_season(1, 21, 21), library_season(2, 9, 22), library_season(3, 0, 13)]

      orientation = Orientation.for_series(seasons, in_progress(episode_id(2, 10), 30, 56))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new([2])
    end

    test "unstarted series opens season one" do
      seasons = [library_season(1, 0, 21), library_season(2, 0, 15)]

      orientation = Orientation.for_series(seasons, unstarted(episode_id(1, 1), 36))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new([1])
    end

    test "complete series opens nothing — the rows are a rewatch index" do
      orientation = Orientation.for_series([library_season(1, 5, 5)], complete(5))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new()
    end

    test "a next episode that is not among the rows opens nothing" do
      empty = %TitleProgress{state: :unstarted, next: nil, before_next: 0, total: 0}

      assert [future_season(1)]
             |> Orientation.for_series(empty)
             |> Orientation.initial_expanded_seasons() == MapSet.new()

      stale = in_progress("gone", 1, 5)

      assert [library_season(1, 1, 5)]
             |> Orientation.for_series(stale)
             |> Orientation.initial_expanded_seasons() ==
               MapSet.new()
    end
  end

  describe "for_series/2 autoscroll" do
    test "mid-series scrolls to the next episode" do
      seasons = [library_season(1, 21, 21), library_season(2, 9, 22)]

      assert Orientation.for_series(seasons, in_progress(episode_id(2, 10), 30, 43)).autoscroll?
    end

    test "unstarted series stays on the hero" do
      progress = unstarted(episode_id(1, 1), 21)
      refute Orientation.for_series([library_season(1, 0, 21)], progress).autoscroll?
    end

    test "a series in progress on its first episode stays on the hero: there is nothing above to scroll past" do
      progress = %TitleProgress{
        state: :in_progress,
        next: next(episode_id(1, 1), 600.0),
        before_next: 0,
        total: 21
      }

      refute Orientation.for_series([library_season(1, 0, 21)], progress).autoscroll?
    end

    test "complete series stays on the hero" do
      refute Orientation.for_series([library_season(1, 5, 5)], complete(5)).autoscroll?
    end

    test "a next episode that is not among the rows is not scrolled to" do
      refute Orientation.for_series([library_season(1, 1, 5)], in_progress("gone", 1, 5)).autoscroll?
    end
  end

  describe "for_collection/2" do
    test "mid-collection: the measure reads the whole collection, autoscroll returns to the next movie" do
      orientation = Orientation.for_collection(collection_items(1, 3), in_progress(movie_id(2), 1, 3))

      assert orientation.season == nil
      assert orientation.fraction == 0.33
      assert orientation.autoscroll?
    end

    test "unstarted collection stays on the hero — a first movie, not a next one" do
      orientation = Orientation.for_collection(collection_items(0, 3), unstarted(movie_id(1), 3))

      assert orientation.fraction == 0.0
      refute orientation.autoscroll?
    end

    test "complete collection reads finished, not empty" do
      orientation = Orientation.for_collection(collection_items(3, 3), complete(3))

      assert orientation.fraction == 1.0
      refute orientation.autoscroll?
    end

    test "mid-collection with no row for the next movie does not autoscroll" do
      items = [upcoming_part(900_001) | collection_items(1, 2)]

      refute Orientation.for_collection(items, in_progress("gone", 1, 3)).autoscroll?
    end

    test "collection accordion projection opens nothing — there are no seasons" do
      orientation = Orientation.for_collection(collection_items(1, 3), in_progress(movie_id(2), 1, 3))

      assert Orientation.initial_expanded_seasons(orientation) == MapSet.new()
    end
  end

  # subline/marquee/overline were removed 2026-08-05: the up-next block
  # duplicated the Play button's own label, so the hairline is the only
  # orientation element the hero renders.
end
