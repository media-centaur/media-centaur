defmodule MediaCentarr.Acquisition.TitleMatcherTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{SearchResult, TitleMatcher}
  alias MediaCentarr.Acquisition.Pursuits.Pursuit

  defp result(title) do
    %SearchResult{title: title, guid: "g", indexer_id: 1}
  end

  defp tv_pursuit(attrs) do
    Map.merge(%Pursuit{recipe_type: "tmdb", tmdb_type: "tv"}, attrs)
  end

  defp movie_pursuit(attrs) do
    Map.merge(%Pursuit{recipe_type: "tmdb", tmdb_type: "movie"}, attrs)
  end

  describe "matches?/2 — TV episode" do
    test "exact title and S/E match" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 1, episode_number: 1})

      assert TitleMatcher.matches?(result("Sample.Show.S01E01.1080p.WEB-DL.x264-GROUP"), pursuit)
      assert TitleMatcher.matches?(result("Sample Show S01E01 1080p WEB-DL"), pursuit)
      assert TitleMatcher.matches?(result("Sample.Show.2025.S01E01.1080p.WEB-DL"), pursuit)
    end

    test "rejects when parsed show name differs" do
      pursuit = tv_pursuit(%{title: "Sample Show Fifteen", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample Show Fifteen.PD.S01E01.1080p.WEB-DL"), pursuit)
      refute TitleMatcher.matches?(result("Sample Show Fifteen.Run.S01E01.1080p.WEB-DL"), pursuit)
      refute TitleMatcher.matches?(result("Sample Show Fifteen.Falls.S01E01.1080p.WEB-DL"), pursuit)
    end

    test "rejects when show name appears as the episode title (the Sample Show Fifteen bug)" do
      pursuit = tv_pursuit(%{title: "Sample Show Fifteen", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(
               result("Sample.Show.S01E05.Sample Show Fifteen.1080p.WEB-DL.x264-GROUP"),
               pursuit
             )

      refute TitleMatcher.matches?(
               result("Another.Series.S02E03.Sample Show Fifteen.Lost.1080p.WEB-DL"),
               pursuit
             )
    end

    test "rejects wrong season" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.S02E01.1080p.WEB-DL"), pursuit)
    end

    test "rejects wrong episode" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.S01E05.1080p.WEB-DL"), pursuit)
    end

    test "rejects movie release for TV pursuit" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("Sample.Show.2025.1080p.WEB-DL.x264-GROUP"), pursuit)
    end

    test "rejects unparseable release" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 1, episode_number: 1})

      refute TitleMatcher.matches?(result("totally.unrelated.gibberish"), pursuit)
      refute TitleMatcher.matches?(result(""), pursuit)
    end

    test "normalises punctuation when comparing titles" do
      pursuit = tv_pursuit(%{title: "Samples Show Twelve", season_number: 1, episode_number: 1})

      assert TitleMatcher.matches?(result("Sample's.Show.Twelve.S01E01.1080p.WEB-DL"), pursuit)
    end

    test "case insensitive" do
      pursuit = tv_pursuit(%{title: "sample show", season_number: 1, episode_number: 1})

      assert TitleMatcher.matches?(result("SAMPLE.SHOW.S01E01.1080p.WEB-DL"), pursuit)
    end
  end

  describe "matches?/2 — TV season pack (episode_number nil)" do
    test "season-pack release matches season-pack pursuit" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 2, episode_number: nil})

      assert TitleMatcher.matches?(result("Sample.Show.S02.Complete.1080p.WEB-DL"), pursuit)
    end

    test "individual episode release does NOT match season-pack pursuit" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 2, episode_number: nil})

      refute TitleMatcher.matches?(result("Sample.Show.S02E01.1080p.WEB-DL"), pursuit)
    end

    test "wrong season pack rejected" do
      pursuit = tv_pursuit(%{title: "Sample Show", season_number: 2, episode_number: nil})

      refute TitleMatcher.matches?(result("Sample.Show.S03.Complete.1080p.WEB-DL"), pursuit)
    end
  end

  describe "matches?/2 — movie" do
    test "matches title and year" do
      pursuit = movie_pursuit(%{title: "Sample Movie", year: 2024})

      assert TitleMatcher.matches?(
               result("Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT"),
               pursuit
             )

      assert TitleMatcher.matches?(result("Sample.Movie.2024.1080p.WEB-DL.H264-NTG"), pursuit)
    end

    test "rejects when year differs" do
      pursuit = movie_pursuit(%{title: "Sample Movie", year: 2024})

      refute TitleMatcher.matches?(result("Sample.Movie.1995.1080p.BluRay.x264"), pursuit)
    end

    test "rejects when title differs" do
      pursuit = movie_pursuit(%{title: "Sample Movie", year: 2024})

      refute TitleMatcher.matches?(result("Different.Movie.2024.1080p.WEB-DL"), pursuit)
    end

    test "rejects TV release for movie pursuit" do
      pursuit = movie_pursuit(%{title: "Sample Show", year: 2024})

      refute TitleMatcher.matches?(result("Sample.Show.S01E01.1080p.WEB-DL"), pursuit)
    end

    test "permissive when pursuit has no year" do
      pursuit = movie_pursuit(%{title: "Sample Movie", year: nil})

      assert TitleMatcher.matches?(result("Sample.Movie.2024.1080p.WEB-DL"), pursuit)
    end
  end
end
