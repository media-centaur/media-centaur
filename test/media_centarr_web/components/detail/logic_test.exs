defmodule MediaCentarrWeb.Components.Detail.LogicTest do
  use ExUnit.Case, async: true

  import MediaCentarr.TestFactory

  alias MediaCentarrWeb.Components.Detail.Logic

  describe "stat_grid_for/2 with :movie" do
    test "returns Director / Original language / Country / Studio in order" do
      movie =
        build_movie(%{
          director: "F. W. Murnau",
          original_language: "de",
          country_code: "DE",
          studio: "Prana Film"
        })

      assert Logic.stat_grid_for(:movie, movie) == [
               {"Director", "F. W. Murnau"},
               {"Original language", "de"},
               {"Country", "DE"},
               {"Studio", "Prana Film"}
             ]
    end

    test "omits cells whose value is nil" do
      movie = build_movie(%{director: "Someone", original_language: nil, country_code: nil, studio: nil})

      assert Logic.stat_grid_for(:movie, movie) == [{"Director", "Someone"}]
    end

    test "omits cells whose value is empty string" do
      movie = build_movie(%{director: "", original_language: "en", country_code: "", studio: "  "})

      assert Logic.stat_grid_for(:movie, movie) == [{"Original language", "en"}]
    end

    test "returns empty list when nothing is populated" do
      assert Logic.stat_grid_for(:movie, build_movie()) == []
    end
  end

  describe "stat_grid_for/2 with :tv_series" do
    test "returns Network / Original language / Country / Status in order" do
      tv =
        build_tv_series(%{
          network: "ABC",
          original_language: "en",
          country_code: "US",
          status: :ended
        })

      assert Logic.stat_grid_for(:tv_series, tv) == [
               {"Network", "ABC"},
               {"Original language", "en"},
               {"Country", "US"},
               {"Status", "Ended"}
             ]
    end

    test "humanizes status atom" do
      tv = build_tv_series(%{status: :returning})
      assert {"Status", "Returning"} in Logic.stat_grid_for(:tv_series, tv)
    end

    test "omits status when nil" do
      tv = build_tv_series(%{network: "HBO", status: nil})
      grid = Logic.stat_grid_for(:tv_series, tv)
      refute Enum.any?(grid, fn {label, _} -> label == "Status" end)
    end
  end

  describe "stat_grid_for/3 with :movie_series" do
    test "returns Movies / First released / Latest derived from member movies" do
      movies = [
        build_movie(%{date_published: "1977-05-25", position: 1}),
        build_movie(%{date_published: "1980-05-21", position: 2}),
        build_movie(%{date_published: "1983-05-25", position: 3})
      ]

      movie_series = build_movie_series(%{movies: movies})

      grid = Logic.stat_grid_for(:movie_series, movie_series, movies)

      assert {"Movies", "3"} in grid
      assert {"First released", "1977"} in grid
      assert {"Latest", "1983"} in grid
    end

    test "tolerates movies missing date_published" do
      movies = [
        build_movie(%{date_published: nil}),
        build_movie(%{date_published: "1999-12-31"})
      ]

      grid = Logic.stat_grid_for(:movie_series, build_movie_series(), movies)

      assert {"Movies", "2"} in grid
      assert {"First released", "1999"} in grid
      assert {"Latest", "1999"} in grid
    end

    test "shows movie count even when no dates available" do
      movies = [build_movie(%{date_published: nil}), build_movie(%{date_published: nil})]
      grid = Logic.stat_grid_for(:movie_series, build_movie_series(), movies)

      assert {"Movies", "2"} in grid
      refute Enum.any?(grid, fn {label, _} -> label == "First released" end)
      refute Enum.any?(grid, fn {label, _} -> label == "Latest" end)
    end

    test "returns empty list when there are no movies" do
      assert Logic.stat_grid_for(:movie_series, build_movie_series(), []) == []
    end
  end

  describe "score_visible?/1" do
    test "true when entity has a rating value" do
      assert Logic.score_visible?(build_movie(%{aggregate_rating_value: 7.9}))
    end

    test "false when rating is nil" do
      refute Logic.score_visible?(build_movie(%{aggregate_rating_value: nil}))
    end

    test "false when rating is 0.0 (TMDB default for unrated)" do
      refute Logic.score_visible?(build_movie(%{aggregate_rating_value: 0.0}))
    end
  end

  describe "year_from_date/1" do
    test "extracts year from ISO date string" do
      assert Logic.year_from_date("2008-07-18") == "2008"
    end

    test "returns nil for nil input" do
      assert Logic.year_from_date(nil) == nil
    end

    test "returns nil for empty string" do
      assert Logic.year_from_date("") == nil
    end

    test "returns nil for malformed date" do
      assert Logic.year_from_date("not-a-date") == nil
    end
  end

  describe "format_duration/1" do
    test "formats ISO 8601 duration to human form" do
      assert Logic.format_duration("PT1H55M") == "1h 55m"
      assert Logic.format_duration("PT2H32M") == "2h 32m"
      assert Logic.format_duration("PT45M") == "45m"
    end

    test "returns nil for nil and empty input" do
      assert Logic.format_duration(nil) == nil
      assert Logic.format_duration("") == nil
    end

    test "returns nil for malformed (non-ISO) strings instead of crashing" do
      assert Logic.format_duration("90 minutes") == nil
      assert Logic.format_duration("garbage") == nil
    end
  end

  describe "humanize_status/1" do
    test "title-cases atom statuses" do
      assert Logic.humanize_status(:released) == "Released"
      assert Logic.humanize_status(:in_production) == "In production"
      assert Logic.humanize_status(:post_production) == "Post production"
      assert Logic.humanize_status(:returning) == "Returning"
    end

    test "passes through string statuses" do
      assert Logic.humanize_status("Released") == "Released"
    end

    test "nil → nil" do
      assert Logic.humanize_status(nil) == nil
    end
  end
end
