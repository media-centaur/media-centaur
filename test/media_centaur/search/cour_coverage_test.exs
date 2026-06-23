defmodule MediaCentaur.Search.CourCoverageTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.CourCoverage

  # Synthetic release-name shapes with a generic placeholder title.
  # The run: TMDB season 1, episodes 29–38, second broadcast run
  # (index 1 → ordinal 2).
  defp run, do: %{index: 1, first_ep: {1, 29}, last_ep: {1, 38}, date_span: nil}

  describe "classify/3 — matches a later-cour pack to its episode range" do
    test "ordinal-season wording" do
      assert CourCoverage.classify("Sample.Show.2nd.Season.1080p.BluRay", "Sample Show", run()) ==
               {:episodes, 1, 29, 38}
    end

    test "Season N wording where N is the run ordinal" do
      assert CourCoverage.classify("Sample Show Season 2 COMPLETE 1080p", "Sample Show", run()) ==
               {:episodes, 1, 29, 38}
    end

    test "absolute episode range" do
      assert CourCoverage.classify("Sample.Show.29-38.1080p.WEB-DL", "Sample Show", run()) ==
               {:episodes, 1, 29, 38}

      assert CourCoverage.classify("Sample.Show.29–38.1080p", "Sample Show", run()) ==
               {:episodes, 1, 29, 38}
    end
  end

  describe "classify/3 — refuses the wrong thing" do
    test "a different show with the right tokens is no_match" do
      assert CourCoverage.classify("Other Show 2nd Season 1080p", "Sample Show", run()) == :no_match
    end

    test "the FIRST-run pack (Season 1 / 1-28) never matches a later run" do
      assert CourCoverage.classify("Sample Show Season 1 COMPLETE", "Sample Show", run()) == :no_match
      assert CourCoverage.classify("Sample.Show.1-28.1080p", "Sample Show", run()) == :no_match
    end

    test "identity match but no run token is no_match" do
      assert CourCoverage.classify("Sample Show 1080p WEB-DL", "Sample Show", run()) == :no_match
    end

    test "the first run (index 0) is never cour-classified" do
      first_run = %{index: 0, first_ep: {1, 1}, last_ep: {1, 28}, date_span: nil}
      assert CourCoverage.classify("Sample Show Season 1", "Sample Show", first_run) == :no_match
    end
  end

  describe "classify/3 — single-episode run" do
    test "a dashed single number maps to a single-episode scope" do
      single = %{index: 1, first_ep: {1, 29}, last_ep: {1, 29}, date_span: nil}
      assert CourCoverage.classify("Sample Show - 29 1080p", "Sample Show", single) == {:episode, 1, 29}
    end
  end
end
