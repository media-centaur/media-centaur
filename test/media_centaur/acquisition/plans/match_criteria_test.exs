defmodule MediaCentaur.Acquisition.Plans.MatchCriteriaTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.{MatchCriteria, Plan}
  alias MediaCentaur.Search.Criteria

  test "a movie plan identifies its title by year and by every id TMDB supplied" do
    plan = %Plan{
      tmdb_type: "movie",
      tmdb_id: "603",
      title: "Sample Movie",
      year: 2010,
      imdb_id: "tt0133093"
    }

    assert %Criteria{
             type: :tmdb,
             tmdb_type: :movie,
             title: "Sample Movie",
             year: 2010,
             tmdb_id: "603",
             imdb_id: "tt0133093",
             tvdb_id: nil
           } = MatchCriteria.from(plan)
  end

  test "a series plan carries its origin countries and its TVDB id" do
    plan = %Plan{
      tmdb_type: "tv",
      tmdb_id: "1396",
      title: "Sample Show",
      origin_country: ["US"],
      imdb_id: "tt0903747",
      tvdb_id: "81189"
    }

    assert %Criteria{
             type: :tmdb,
             tmdb_type: :tv,
             title: "Sample Show",
             origin_country: ["US"],
             tmdb_id: "1396",
             imdb_id: "tt0903747",
             tvdb_id: "81189",
             season_number: nil,
             episode_number: nil
           } = MatchCriteria.from(plan)
  end

  test "a plan with no origin countries recorded reads as unknown origin, not a crash" do
    assert %Criteria{origin_country: []} =
             MatchCriteria.from(%Plan{tmdb_type: "tv", tmdb_id: "1", title: "Sample Show"})
  end
end
