defmodule MediaCentarr.Search.TitleMatcherTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Search.{Criteria, SearchResult, TitleMatcher}

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
end
