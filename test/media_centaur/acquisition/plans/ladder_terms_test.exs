defmodule MediaCentaur.Acquisition.Plans.LadderTermsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.{LadderTerms, Plan}

  defp plan, do: %Plan{title: "Sample Show", tmdb_type: "tv"}

  describe "rung constructors" do
    test "series_terms/1 is the one broad term" do
      assert LadderTerms.series_terms(plan()) == [{"Sample Show", [type: :tv]}]
    end

    test "season_terms/2 emits both text forms per season, in order" do
      assert LadderTerms.season_terms(plan(), [1, 3]) == [
               {"Sample Show Season 1", [type: :tv]},
               {"Sample Show S01", [type: :tv]},
               {"Sample Show Season 3", [type: :tv]},
               {"Sample Show S03", [type: :tv]}
             ]
    end

    test "episode_terms/2 emits one zero-padded term per unit" do
      assert LadderTerms.episode_terms(plan(), [{1, 2}, {10, 11}]) == [
               {"Sample Show S01E02", [type: :tv]},
               {"Sample Show S10E11", [type: :tv]}
             ]
    end
  end

  describe "the for_plan invariant" do
    # for_unit/2 (the swap picker's term universe) and the corpus keys
    # both build on for_plan/2 — the rung constructors must concatenate
    # to exactly it, or lazy descent and the picker drift apart.
    test "for_plan/2 is series ++ seasons ++ episodes" do
      wanted = [{2, 1}, {1, 3}, {1, 1}]
      seasons = wanted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

      assert LadderTerms.for_plan(plan(), wanted) ==
               LadderTerms.series_terms(plan()) ++
                 LadderTerms.season_terms(plan(), seasons) ++
                 LadderTerms.episode_terms(plan(), wanted)
    end

    test "movie plans are unaffected" do
      movie_plan = %Plan{title: "Sample Movie", tmdb_type: "movie", year: 2010}
      assert LadderTerms.for_plan(movie_plan, []) == [{"Sample Movie 2010", [type: :movie]}]
    end
  end
end
