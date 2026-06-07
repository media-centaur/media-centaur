defmodule MediaCentaur.Library.CompletenessTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.Completeness

  describe "detect_season_gaps/1 (pure)" do
    test "no gaps when episode numbers are contiguous" do
      rows = [
        %{tv_series_id: "a", season_number: 1, episode_number: 1},
        %{tv_series_id: "a", season_number: 1, episode_number: 2},
        %{tv_series_id: "a", season_number: 1, episode_number: 3}
      ]

      assert Completeness.detect_season_gaps(rows) == 0
    end

    test "counts a series with an internal gap in a season" do
      rows = [
        %{tv_series_id: "a", season_number: 1, episode_number: 1},
        %{tv_series_id: "a", season_number: 1, episode_number: 2},
        %{tv_series_id: "a", season_number: 1, episode_number: 4}
      ]

      assert Completeness.detect_season_gaps(rows) == 1
    end

    test "counts a series only once even when multiple seasons have gaps" do
      rows = [
        %{tv_series_id: "a", season_number: 1, episode_number: 1},
        %{tv_series_id: "a", season_number: 1, episode_number: 3},
        %{tv_series_id: "a", season_number: 2, episode_number: 1},
        %{tv_series_id: "a", season_number: 2, episode_number: 5}
      ]

      assert Completeness.detect_season_gaps(rows) == 1
    end

    test "counts each distinct series with a gap" do
      rows = [
        %{tv_series_id: "a", season_number: 1, episode_number: 1},
        %{tv_series_id: "a", season_number: 1, episode_number: 3},
        %{tv_series_id: "b", season_number: 1, episode_number: 2},
        %{tv_series_id: "b", season_number: 1, episode_number: 9}
      ]

      assert Completeness.detect_season_gaps(rows) == 2
    end

    test "ignores nil episode numbers and empty input" do
      assert Completeness.detect_season_gaps([]) == 0

      rows = [
        %{tv_series_id: "a", season_number: 1, episode_number: nil},
        %{tv_series_id: "a", season_number: 1, episode_number: 1}
      ]

      assert Completeness.detect_season_gaps(rows) == 0
    end
  end

  describe "incomplete_season_count/0" do
    test "counts series with a missing episode in the middle of a season" do
      series = create_tv_series(%{name: "Gappy Show"})
      season = create_season(%{season_number: 1, tv_series_id: series.id})
      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 3, season_id: season.id})

      assert Completeness.incomplete_season_count() == 1
    end

    test "does not count a series whose seasons are contiguous" do
      series = create_tv_series(%{name: "Complete Show"})
      season = create_season(%{season_number: 1, tv_series_id: series.id})
      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 2, season_id: season.id})

      assert Completeness.incomplete_season_count() == 0
    end
  end

  describe "missing_metadata_count/0" do
    test "counts library containers with no TMDB external id" do
      create_movie(%{name: "Unmatched Movie"})

      assert Completeness.missing_metadata_count() == 1
    end

    test "excludes containers that have a TMDB external id" do
      create_movie(%{name: "Matched Movie", tmdb_id: "12345"})

      assert Completeness.missing_metadata_count() == 0
    end

    test "uses the collection source for movie series" do
      create_movie_series(%{name: "Unmatched Collection"})
      create_movie_series(%{name: "Matched Collection", tmdb_id: "999"})

      assert Completeness.missing_metadata_count() == 1
    end

    test "returns zero for an empty library" do
      assert Completeness.missing_metadata_count() == 0
    end
  end
end
