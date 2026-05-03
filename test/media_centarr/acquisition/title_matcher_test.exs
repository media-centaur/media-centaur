defmodule MediaCentarr.Acquisition.TitleMatcherTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{Grab, SearchResult, TitleMatcher}

  defp result(title) do
    %SearchResult{title: title, guid: "g", indexer_id: 1}
  end

  describe "matches?/2 — TV episode" do
    test "exact title and S/E match" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 1
      }

      assert TitleMatcher.matches?(result("Sample.Show.S01E01.1080p.WEB-DL.x264-GROUP"), grab)
      assert TitleMatcher.matches?(result("Sample Show S01E01 1080p WEB-DL"), grab)
      assert TitleMatcher.matches?(result("Sample.Show.2025.S01E01.1080p.WEB-DL"), grab)
    end

    test "rejects when parsed show name differs" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show Fifteen",
        season_number: 1,
        episode_number: 1
      }

      refute TitleMatcher.matches?(result("Sample Show Fifteen.PD.S01E01.1080p.WEB-DL"), grab)
      refute TitleMatcher.matches?(result("Sample Show Fifteen.Run.S01E01.1080p.WEB-DL"), grab)
      refute TitleMatcher.matches?(result("Sample Show Fifteen.Falls.S01E01.1080p.WEB-DL"), grab)
    end

    test "rejects when show name appears as the episode title (the Sample Show Fifteen bug)" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show Fifteen",
        season_number: 1,
        episode_number: 1
      }

      refute TitleMatcher.matches?(
               result("Sample.Show.S01E05.Sample Show Fifteen.1080p.WEB-DL.x264-GROUP"),
               grab
             )

      refute TitleMatcher.matches?(
               result("Another.Series.S02E03.Sample Show Fifteen.Lost.1080p.WEB-DL"),
               grab
             )
    end

    test "rejects wrong season" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 1
      }

      refute TitleMatcher.matches?(result("Sample.Show.S02E01.1080p.WEB-DL"), grab)
    end

    test "rejects wrong episode" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 1
      }

      refute TitleMatcher.matches?(result("Sample.Show.S01E05.1080p.WEB-DL"), grab)
    end

    test "rejects movie release for TV grab" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 1
      }

      refute TitleMatcher.matches?(result("Sample.Show.2025.1080p.WEB-DL.x264-GROUP"), grab)
    end

    test "rejects unparseable release" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 1
      }

      refute TitleMatcher.matches?(result("totally.unrelated.gibberish"), grab)
      refute TitleMatcher.matches?(result(""), grab)
    end

    test "normalises punctuation when comparing titles" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Samples Show Twelve",
        season_number: 1,
        episode_number: 1
      }

      assert TitleMatcher.matches?(result("Sample's.Show.Twelve.S01E01.1080p.WEB-DL"), grab)
    end

    test "case insensitive" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "sample show",
        season_number: 1,
        episode_number: 1
      }

      assert TitleMatcher.matches?(result("SAMPLE.SHOW.S01E01.1080p.WEB-DL"), grab)
    end
  end

  describe "matches?/2 — TV season pack (episode_number nil)" do
    test "season-pack release matches season-pack grab" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 2,
        episode_number: nil
      }

      assert TitleMatcher.matches?(result("Sample.Show.S02.Complete.1080p.WEB-DL"), grab)
    end

    test "individual episode release does NOT match season-pack grab" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 2,
        episode_number: nil
      }

      refute TitleMatcher.matches?(result("Sample.Show.S02E01.1080p.WEB-DL"), grab)
    end

    test "wrong season pack rejected" do
      grab = %Grab{
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 2,
        episode_number: nil
      }

      refute TitleMatcher.matches?(result("Sample.Show.S03.Complete.1080p.WEB-DL"), grab)
    end
  end

  describe "matches?/2 — movie" do
    test "matches title and year" do
      grab = %Grab{tmdb_type: "movie", title: "Sample Movie", year: 2024}

      assert TitleMatcher.matches?(
               result("Sample.Movie.2024.2160p.UHD.BluRay.REMUX-FGT"),
               grab
             )

      assert TitleMatcher.matches?(result("Sample.Movie.2024.1080p.WEB-DL.H264-NTG"), grab)
    end

    test "rejects when year differs" do
      grab = %Grab{tmdb_type: "movie", title: "Sample Movie", year: 2024}

      refute TitleMatcher.matches?(result("Sample.Movie.1995.1080p.BluRay.x264"), grab)
    end

    test "rejects when title differs" do
      grab = %Grab{tmdb_type: "movie", title: "Sample Movie", year: 2024}

      refute TitleMatcher.matches?(result("Different.Movie.2024.1080p.WEB-DL"), grab)
    end

    test "rejects TV release for movie grab" do
      grab = %Grab{tmdb_type: "movie", title: "Sample Show", year: 2024}

      refute TitleMatcher.matches?(result("Sample.Show.S01E01.1080p.WEB-DL"), grab)
    end

    test "permissive when grab has no year" do
      grab = %Grab{tmdb_type: "movie", title: "Sample Movie", year: nil}

      assert TitleMatcher.matches?(result("Sample.Movie.2024.1080p.WEB-DL"), grab)
    end
  end
end
