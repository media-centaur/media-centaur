defmodule MediaCentaur.Search.TitleMatcherTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.{Criteria, SearchResult, TitleMatcher}

  defp result(title) do
    %SearchResult{title: title, guid: "g", indexer_id: 1}
  end

  defp tv_criteria(attrs) do
    Map.merge(%Criteria{type: :tmdb, title: "n/a", tmdb_type: :tv}, attrs)
  end

  defp movie_criteria(attrs) do
    Map.merge(%Criteria{type: :tmdb, title: "n/a", tmdb_type: :movie}, attrs)
  end

  describe "matches?/2 — TV episode" do
    test "exact title and S/E match" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 1})

      assert TitleMatcher.matches?(result("Sample.Show.S01E01.1080p.WEB-DL.x264-GROUP"), criteria)
      assert TitleMatcher.matches?(result("Sample Show S01E01 1080p WEB-DL"), criteria)
      assert TitleMatcher.matches?(result("Sample.Show.2025.S01E01.1080p.WEB-DL"), criteria)
    end

    test "rejects when parsed show name differs" do
      criteria = tv_criteria(%{title: "Sample Show Fifteen", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample Show Fifteen.PD.S01E01.1080p.WEB-DL"), criteria)
      refute TitleMatcher.matches?(result("Sample Show Fifteen.Run.S01E01.1080p.WEB-DL"), criteria)
      refute TitleMatcher.matches?(result("Sample Show Fifteen.Falls.S01E01.1080p.WEB-DL"), criteria)
    end

    test "rejects when show name appears as the episode title (the Sample Show Fifteen bug)" do
      criteria = tv_criteria(%{title: "Sample Show Fifteen", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(
               result("Sample.Show.S01E05.Sample Show Fifteen.1080p.WEB-DL.x264-GROUP"),
               criteria
             )

      refute TitleMatcher.matches?(
               result("Another.Series.S02E03.Sample Show Fifteen.Lost.1080p.WEB-DL"),
               criteria
             )
    end

    test "rejects wrong season" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.S02E01.1080p.WEB-DL"), criteria)
    end

    test "rejects wrong episode" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.S01E05.1080p.WEB-DL"), criteria)
    end

    test "rejects movie release for TV criteria" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.2025.1080p.WEB-DL.x264-GROUP"), criteria)
    end

    test "rejects unparseable release" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("totally.unrelated.gibberish"), criteria)
      refute TitleMatcher.matches?(result(""), criteria)
    end

    test "normalises punctuation when comparing titles" do
      criteria = tv_criteria(%{title: "Samples Show Twelve", season_number: 1, episode_number: 1})

      assert TitleMatcher.matches?(result("Sample's.Show.Twelve.S01E01.1080p.WEB-DL"), criteria)
    end

    test "case insensitive" do
      criteria = tv_criteria(%{title: "sample show", season_number: 1, episode_number: 1})

      assert TitleMatcher.matches?(result("SAMPLE.SHOW.S01E01.1080p.WEB-DL"), criteria)
    end
  end

  describe "matches?/2 — TV season pack (episode_number nil)" do
    test "season-pack release matches season-pack criteria" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 2, episode_number: nil})

      assert TitleMatcher.matches?(result("Sample.Show.S02.Complete.1080p.WEB-DL"), criteria)
    end

    test "individual episode release does NOT match season-pack criteria" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 2, episode_number: nil})

      refute TitleMatcher.matches?(result("Sample.Show.S02E01.1080p.WEB-DL"), criteria)
    end

    test "wrong season pack rejected" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 2, episode_number: nil})

      refute TitleMatcher.matches?(result("Sample.Show.S03.Complete.1080p.WEB-DL"), criteria)
    end
  end

  describe "matches?/2 — movie" do
    test "matches title and year" do
      criteria = movie_criteria(%{title: "Sample Movie", year: 2024})

      assert TitleMatcher.matches?(
               result("Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT"),
               criteria
             )

      assert TitleMatcher.matches?(result("Sample.Movie.2024.1080p.WEB-DL.H264-NTG"), criteria)
    end

    test "rejects when year differs" do
      criteria = movie_criteria(%{title: "Sample Movie", year: 2024})

      refute TitleMatcher.matches?(result("Sample.Movie.1995.1080p.BluRay.x264"), criteria)
    end

    test "rejects when title differs" do
      criteria = movie_criteria(%{title: "Sample Movie", year: 2024})

      refute TitleMatcher.matches?(result("Different.Movie.2024.1080p.WEB-DL"), criteria)
    end

    test "rejects TV release for movie criteria" do
      criteria = movie_criteria(%{title: "Sample Show", year: 2024})

      refute TitleMatcher.matches?(result("Sample.Show.S01E01.1080p.WEB-DL"), criteria)
    end

    test "permissive when criteria has no year" do
      criteria = movie_criteria(%{title: "Sample Movie", year: nil})

      assert TitleMatcher.matches?(result("Sample.Movie.2024.1080p.WEB-DL"), criteria)
    end
  end

  describe "coverage/2 — identity + scope for the coverage ladder (ADR-055 Phase 2)" do
    test "an exact-episode release for the right show reads as its episode scope" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 3})

      assert {:ok, {:episode, 1, 3}} =
               TitleMatcher.coverage(result("Sample.Show.S01E03.1080p.WEB-DL.x264-GROUP"), criteria)
    end

    test "a season pack for the right show reads as its season scope" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 2})

      assert {:ok, {:season, 2}} =
               TitleMatcher.coverage(result("Sample.Show.S02.COMPLETE.1080p.WEB-DL"), criteria)
    end

    test "a multi-season range and a complete series read as their scopes" do
      criteria = tv_criteria(%{title: "Sample Show"})

      assert {:ok, {:seasons, 1, 5}} =
               TitleMatcher.coverage(result("Sample.Show.S01-S05.1080p.WEB-DL.x264"), criteria)

      assert {:ok, :series} =
               TitleMatcher.coverage(result("Sample.Show.COMPLETE.1080p.WEB-DL"), criteria)
    end

    test "the wrong show never matches, whatever its scope" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 2})

      assert :no_match = TitleMatcher.coverage(result("Other.Show.S02.COMPLETE.1080p"), criteria)
      assert :no_match = TitleMatcher.coverage(result("Other.Show.S02E01.1080p"), criteria)
      assert :no_match = TitleMatcher.coverage(result("Sample.Show.Fifteen.S02.1080p"), criteria)
    end

    test "a year token in the release title is tolerated for identity" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 2})

      assert {:ok, {:season, 2}} =
               TitleMatcher.coverage(result("Sample.Show.2025.S02.COMPLETE.1080p"), criteria)
    end

    test "movie criteria and unclassifiable titles read as no_match" do
      movie = movie_criteria(%{title: "Sample Movie"})
      assert :no_match = TitleMatcher.coverage(result("Sample.Movie.2010.1080p.BluRay"), movie)

      tv = tv_criteria(%{title: "Sample Show"})
      assert :no_match = TitleMatcher.coverage(result("Sample Show behind the scenes featurette"), tv)
    end

    test "prowlarr_query criteria never coverage-match (no canonical title to verify)" do
      criteria = %Criteria{type: :prowlarr_query, title: "n/a"}
      assert :no_match = TitleMatcher.coverage(result("Sample.Show.S01.COMPLETE.1080p"), criteria)
    end
  end

  describe "coverage/2 — scene country tags (remake disambiguation)" do
    test "a season pack tagged with the show's origin country matches" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["US"]})

      assert {:ok, {:season, 1}} =
               TitleMatcher.coverage(result("Sample.Show.US.S01.1080p.BluRay.x264-GROUP"), criteria)
    end

    test "a complete-series release tagged with the origin country matches" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["US"]})

      assert {:ok, :series} =
               TitleMatcher.coverage(result("Sample.Show.US.COMPLETE.1080p.WEB-DL"), criteria)
    end

    test "an episode tagged with the origin country matches" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["US"]})

      assert {:ok, {:episode, 1, 3}} =
               TitleMatcher.coverage(result("Sample.Show.US.S01E03.720p.BluRay.x264-GROUP"), criteria)
    end

    test "a country tag outside the show's origin countries is rejected" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["AU"]})

      assert :no_match =
               TitleMatcher.coverage(result("Sample.Show.US.S01.1080p.BluRay.x264-GROUP"), criteria)

      assert :no_match =
               TitleMatcher.coverage(result("Sample.Show.US.S01E03.720p.BluRay.x264-GROUP"), criteria)
    end

    test "a country tag is rejected when the criteria carry no origin countries" do
      criteria = tv_criteria(%{title: "Sample Show"})

      assert :no_match =
               TitleMatcher.coverage(result("Sample.Show.US.S01.1080p.BluRay.x264-GROUP"), criteria)
    end

    test "the scene UK tag maps to TMDB's GB origin code" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["GB"]})

      assert {:ok, {:season, 2}} =
               TitleMatcher.coverage(result("Sample.Show.UK.S02.COMPLETE.1080p.WEB-DL"), criteria)
    end

    test "a country tag combined with a year token is tolerated" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["US"]})

      assert {:ok, {:season, 1}} =
               TitleMatcher.coverage(result("Sample.Show.US.2011.S01.1080p.BluRay"), criteria)
    end

    test "an untagged release still matches regardless of origin countries" do
      criteria = tv_criteria(%{title: "Sample Show", origin_country: ["US"]})

      assert {:ok, {:season, 1}} =
               TitleMatcher.coverage(result("Sample.Show.S01.1080p.BluRay.x264-GROUP"), criteria)
    end

    test "matches?/2 accepts an origin-tagged episode for the auto-grab gate" do
      criteria =
        tv_criteria(%{
          title: "Sample Show",
          season_number: 1,
          episode_number: 1,
          origin_country: ["US"]
        })

      assert TitleMatcher.matches?(result("Sample.Show.US.S01E01.1080p.WEB-DL.x264-GROUP"), criteria)
    end

    test "matches?/2 rejects an origin-tagged episode when origins are unknown" do
      criteria = tv_criteria(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.US.S01E01.1080p.WEB-DL.x264-GROUP"), criteria)
    end
  end
end
