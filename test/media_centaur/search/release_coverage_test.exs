defmodule MediaCentaur.Search.ReleaseCoverageTest do
  # Release-title classification tests are parser-class regression tests:
  # append-only per ADR-027. Every title here is a realistic release-name
  # shape using generic placeholders (no real show titles).
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.ReleaseCoverage

  describe "classify/1 — single episode" do
    test "standard SxxExx" do
      assert ReleaseCoverage.classify("Sample.Show.S01E03.1080p.WEB-DL.x264-GROUP") ==
               {:episode, 1, 3}

      assert ReleaseCoverage.classify("Sample Show S02E11 720p") == {:episode, 2, 11}
    end
  end

  describe "classify/1 — episode span" do
    test "SxxEyy-Ezz" do
      assert ReleaseCoverage.classify("Sample.Show.S01E01-E05.1080p.WEB-DL") ==
               {:episodes, 1, 1, 5}
    end

    test "SxxEyy-zz (no second E)" do
      assert ReleaseCoverage.classify("Sample.Show.S01E01-05.1080p") == {:episodes, 1, 1, 5}
    end

    test "en-dash separator (SxxEyy–Ezz)" do
      assert ReleaseCoverage.classify("Sample.Show.S01E01–E05.1080p.WEB-DL") ==
               {:episodes, 1, 1, 5}
    end
  end

  describe "classify/1 — season pack" do
    test "bare season marker" do
      assert ReleaseCoverage.classify("Sample.Show.S02.1080p.WEB-DL.x264-GROUP") == {:season, 2}
    end

    test "Season N wording" do
      assert ReleaseCoverage.classify("Sample Show Season 2 1080p WEB-DL") == {:season, 2}
      assert ReleaseCoverage.classify("Sample.Show.Season.3.COMPLETE.1080p") == {:season, 3}
    end

    test "season marker with COMPLETE token" do
      assert ReleaseCoverage.classify("Sample.Show.S02.COMPLETE.1080p.WEB-DL") == {:season, 2}
    end
  end

  describe "classify/1 — multi-season range" do
    test "S01-S05" do
      assert ReleaseCoverage.classify("Sample.Show.S01-S05.1080p.WEB-DL.x264") ==
               {:seasons, 1, 5}
    end

    test "S01-03 (no second S)" do
      assert ReleaseCoverage.classify("Sample.Show.S01-03.COMPLETE.1080p") == {:seasons, 1, 3}
    end

    test "en-dash separator (Sxx–Syy)" do
      assert ReleaseCoverage.classify("Sample.Show.S01–S05.1080p.WEB-DL.x264") ==
               {:seasons, 1, 5}
    end

    test "inverted ranges are nonsense, not packs" do
      assert ReleaseCoverage.classify("Sample.Show.S05-S01.1080p") == :unknown
    end
  end

  describe "classify/1 — complete series" do
    test "COMPLETE without any season scope" do
      assert ReleaseCoverage.classify("Sample.Show.COMPLETE.1080p.WEB-DL.x264-GROUP") == :series
    end

    test "Complete Series wording" do
      assert ReleaseCoverage.classify("Sample Show Complete Series 1080p") == :series
      assert ReleaseCoverage.classify("Sample.Show.The.Complete.Collection.2160p") == :series
    end
  end

  describe "classify/1 — not packs" do
    test "movie-shaped titles" do
      assert ReleaseCoverage.classify("Sample.Movie.2010.1080p.BluRay.x264-GROUP") == :unknown
    end

    test "resolution tokens don't read as seasons" do
      # 2160p / x265 / 5.1 must never parse as season scope.
      assert ReleaseCoverage.classify("Sample.Movie.2160p.x265.5.1-GROUP") == :unknown
    end
  end

  describe "covers?/3" do
    test "episode covers only itself" do
      assert ReleaseCoverage.covers?({:episode, 1, 3}, 1, 3)
      refute ReleaseCoverage.covers?({:episode, 1, 3}, 1, 4)
      refute ReleaseCoverage.covers?({:episode, 1, 3}, 2, 3)
    end

    test "episode span covers its inclusive range" do
      assert ReleaseCoverage.covers?({:episodes, 1, 2, 5}, 1, 2)
      assert ReleaseCoverage.covers?({:episodes, 1, 2, 5}, 1, 5)
      refute ReleaseCoverage.covers?({:episodes, 1, 2, 5}, 1, 6)
      refute ReleaseCoverage.covers?({:episodes, 1, 2, 5}, 2, 3)
    end

    test "season pack covers every episode of its season" do
      assert ReleaseCoverage.covers?({:season, 2}, 2, 1)
      assert ReleaseCoverage.covers?({:season, 2}, 2, 99)
      refute ReleaseCoverage.covers?({:season, 2}, 1, 1)
    end

    test "season range covers every episode of the spanned seasons" do
      assert ReleaseCoverage.covers?({:seasons, 1, 3}, 2, 7)
      refute ReleaseCoverage.covers?({:seasons, 1, 3}, 4, 1)
    end

    test "complete series covers everything; unknown covers nothing" do
      assert ReleaseCoverage.covers?(:series, 9, 23)
      refute ReleaseCoverage.covers?(:unknown, 1, 1)
    end
  end

  describe "covered_units/2 — the pack→episode accounting primitive" do
    test "a season pack covers exactly the wanted units of its season (partial packs are normal)" do
      wanted = [{1, 1}, {1, 2}, {2, 1}, {2, 2}, {2, 3}]

      assert ReleaseCoverage.covered_units({:season, 2}, wanted) == [{2, 1}, {2, 2}, {2, 3}]
    end

    test "an episode release covers at most one wanted unit" do
      wanted = [{1, 1}, {1, 2}]

      assert ReleaseCoverage.covered_units({:episode, 1, 2}, wanted) == [{1, 2}]
      assert ReleaseCoverage.covered_units({:episode, 3, 1}, wanted) == []
    end

    test "complete series covers all wanted units" do
      wanted = [{1, 1}, {7, 12}]

      assert ReleaseCoverage.covered_units(:series, wanted) == wanted
    end
  end

  describe "scope_label/1" do
    test "labels every scope the classifier can produce" do
      assert ReleaseCoverage.scope_label({:episode, 1, 3}) == "S01E03"
      assert ReleaseCoverage.scope_label({:episodes, 1, 1, 5}) == "S01E01-05"
      assert ReleaseCoverage.scope_label({:season, 2}) == "Season 2 pack"
      assert ReleaseCoverage.scope_label({:seasons, 1, 5}) == "Seasons 1–5 pack"
      assert ReleaseCoverage.scope_label(:series) == "Complete series"
    end

    test "an unknown scope has no label" do
      assert ReleaseCoverage.scope_label(:unknown) == nil
    end
  end
end
