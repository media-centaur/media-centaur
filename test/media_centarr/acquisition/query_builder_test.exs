defmodule MediaCentarr.Acquisition.QueryBuilderTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{Grab, QueryBuilder}

  describe "build/1 — movie" do
    test "includes year and type=:movie when year is present" do
      grab = %Grab{
        tmdb_type: "movie",
        title: "Sample Movie",
        year: 2010,
        season_number: nil,
        episode_number: nil
      }

      assert [{query, opts}] = QueryBuilder.build(grab)
      assert query == "Sample Movie 2010"
      assert Keyword.get(opts, :type) == :movie
      assert Keyword.get(opts, :year) == 2010
    end

    test "omits year and year-opt when year is nil" do
      grab = %Grab{
        tmdb_type: "movie",
        title: "Sample Movie",
        year: nil,
        season_number: nil,
        episode_number: nil
      }

      assert [{query, opts}] = QueryBuilder.build(grab)
      assert query == "Sample Movie"
      assert Keyword.get(opts, :type) == :movie
      refute Keyword.has_key?(opts, :year)
    end
  end

  describe "build/1 — TV episode" do
    test "primary query is 'Title SxxExx', fallback is the season pack" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 3,
        episode_number: 4
      }

      assert [
               {"Sample Show S03E04", primary_opts},
               {"Sample Show Season 3", fallback_opts}
             ] = QueryBuilder.build(grab)

      assert Keyword.get(primary_opts, :type) == :tv
      assert Keyword.get(fallback_opts, :type) == :tv
    end

    test "pads single-digit season and episode" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Show",
        season_number: 1,
        episode_number: 1
      }

      assert [{"Show S01E01", _}, _] = QueryBuilder.build(grab)
    end

    test "preserves double-digit season and episode without padding" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Show",
        season_number: 12,
        episode_number: 23
      }

      assert [{"Show S12E23", _}, _] = QueryBuilder.build(grab)
    end

    test "does not include year on TV queries (release titles do not carry it)" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        year: 2022,
        season_number: 3,
        episode_number: 4
      }

      assert [{_, primary_opts}, {_, fallback_opts}] = QueryBuilder.build(grab)
      refute Keyword.has_key?(primary_opts, :year)
      refute Keyword.has_key?(fallback_opts, :year)
    end
  end

  describe "build/1 — TV season pack (no episode)" do
    test "primary 'Title Season N', fallback 'Title SXX'" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 3,
        episode_number: nil
      }

      assert [
               {"Sample Show Season 3", primary_opts},
               {"Sample Show S03", fallback_opts}
             ] = QueryBuilder.build(grab)

      assert Keyword.get(primary_opts, :type) == :tv
      assert Keyword.get(fallback_opts, :type) == :tv
    end
  end
end
