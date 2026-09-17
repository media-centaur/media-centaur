defmodule MediaCentaur.Search.SearchTermsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Search.{Criteria, SearchTerms}

  defp show(attrs \\ %{}) do
    struct!(%Criteria{type: :tmdb, tmdb_type: :tv, title: "Sample Show"}, attrs)
  end

  defp movie(attrs \\ %{}) do
    struct!(%Criteria{type: :tmdb, tmdb_type: :movie, title: "Sample Movie", year: 2010}, attrs)
  end

  describe "scope constructors" do
    test "series_terms/1 is the one broad term" do
      assert SearchTerms.series_terms(show()) == ["Sample Show"]
    end

    test "apostrophes are stripped from every term (scene names carry none)" do
      tagged_show = show(%{title: "Sample's Show"})

      assert SearchTerms.series_terms(tagged_show) == ["Samples Show"]

      assert SearchTerms.season_terms(tagged_show, [1]) == [
               "Samples Show Season 1",
               "Samples Show S01"
             ]

      assert SearchTerms.episode_terms(tagged_show, [{1, 2}]) == ["Samples Show S01E02"]

      assert SearchTerms.movie_terms(movie(%{title: "Sample's Movie"})) == [
               "Samples Movie 2010",
               "Samples Movie"
             ]
    end

    test "season_terms/2 emits both text forms per season, in order" do
      assert SearchTerms.season_terms(show(), [1, 3]) == [
               "Sample Show Season 1",
               "Sample Show S01",
               "Sample Show Season 3",
               "Sample Show S03"
             ]
    end

    test "episode_terms/2 emits one zero-padded term per unit" do
      assert SearchTerms.episode_terms(show(), [{1, 2}, {10, 11}]) == [
               "Sample Show S01E02",
               "Sample Show S10E11"
             ]
    end
  end

  describe "movie terms" do
    test "a movie's original title is one more phrasing, broadest last" do
      assert SearchTerms.movie_terms(movie(%{original_title: "Le Fabuleux Destin de Sample"})) == [
               "Sample Movie 2010",
               "Sample Movie",
               "Le Fabuleux Destin de Sample"
             ]
    end

    test "an original title matching the canonical one adds no term" do
      assert SearchTerms.movie_terms(movie(%{title: "Amélie", year: 2001, original_title: "Amelie"})) ==
               ["Amelie 2001", "Amelie"]
    end

    test "movie terms fall back from the year term to the year-less term" do
      # Release years drift (festival premiere vs theatrical) — the
      # year-less term keeps a wrong year from becoming a silent miss.
      assert SearchTerms.movie_terms(movie()) == ["Sample Movie 2010", "Sample Movie"]
    end
  end

  describe "search_opts/1" do
    test "scopes every term to the category its media type implies" do
      assert SearchTerms.search_opts(show()) == [categories: :tv]
      assert SearchTerms.search_opts(movie()) == [categories: :movie]
    end
  end
end
