defmodule MediaCentaur.Acquisition.Plans.SearchTermsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Plans.{Plan, SearchTerms}

  defp plan, do: %Plan{title: "Sample Show", tmdb_type: "tv"}

  describe "scope constructors" do
    test "series_terms/1 is the one broad term" do
      assert SearchTerms.series_terms(plan()) == ["Sample Show"]
    end

    test "apostrophes are stripped from every term (scene names carry none)" do
      tagged_plan = %Plan{title: "Sample's Show", tmdb_type: "tv"}

      assert SearchTerms.series_terms(tagged_plan) == ["Samples Show"]

      assert SearchTerms.season_terms(tagged_plan, [1]) == [
               "Samples Show Season 1",
               "Samples Show S01"
             ]

      assert SearchTerms.episode_terms(tagged_plan, [{1, 2}]) == ["Samples Show S01E02"]

      movie_plan = %Plan{title: "Sample's Movie", tmdb_type: "movie", year: 2010}

      assert SearchTerms.movie_terms(movie_plan) == [
               "Samples Movie 2010",
               "Samples Movie"
             ]
    end

    test "season_terms/2 emits both text forms per season, in order" do
      assert SearchTerms.season_terms(plan(), [1, 3]) == [
               "Sample Show Season 1",
               "Sample Show S01",
               "Sample Show Season 3",
               "Sample Show S03"
             ]
    end

    test "episode_terms/2 emits one zero-padded term per unit" do
      assert SearchTerms.episode_terms(plan(), [{1, 2}, {10, 11}]) == [
               "Sample Show S01E02",
               "Sample Show S10E11"
             ]
    end
  end

  describe "movie terms" do
    test "a movie's original title is one more phrasing, broadest last" do
      movie_plan = %Plan{
        title: "Sample Movie",
        tmdb_type: "movie",
        year: 2010,
        original_title: "Le Fabuleux Destin de Sample"
      }

      assert SearchTerms.movie_terms(movie_plan) == [
               "Sample Movie 2010",
               "Sample Movie",
               "Le Fabuleux Destin de Sample"
             ]
    end

    test "an original title matching the canonical one adds no term" do
      movie_plan = %Plan{
        title: "Amélie",
        tmdb_type: "movie",
        year: 2001,
        original_title: "Amelie"
      }

      assert SearchTerms.movie_terms(movie_plan) == ["Amelie 2001", "Amelie"]
    end

    test "movie plans fall back from the year term to the year-less term" do
      # Release years drift (festival premiere vs theatrical) — the
      # year-less term keeps a wrong year from becoming a silent miss.
      movie_plan = %Plan{title: "Sample Movie", tmdb_type: "movie", year: 2010}

      assert SearchTerms.movie_terms(movie_plan) == [
               "Sample Movie 2010",
               "Sample Movie"
             ]
    end
  end
end
