defmodule MediaCentarr.Library.Views.Search.ScorerTest do
  @moduledoc """
  Unit tests for the pure `Library.Views.Search.Scorer` module.

  The scorer is a pure function used by the Search projection's
  `:ets.foldl/3` read path. Keeping it in its own module with
  `async: true` tests gives fast feedback for scoring rule changes
  without booting the data case.

  The scorer expects pre-normalised input (downcase + trim); the caller
  is responsible for normalisation. See `Library.Views.Search` for the
  read-path wiring.
  """
  use ExUnit.Case, async: true

  alias MediaCentarr.Library.Views.Search.Scorer

  describe "score/2 — empty query short-circuit" do
    test "empty query returns 0.0" do
      assert Scorer.score("", "movie a") == 0.0
    end

    test "whitespace-only query returns 0.0" do
      assert Scorer.score("   ", "movie a") == 0.0
    end
  end

  describe "score/2 — exact match" do
    test "exact match returns 1.0" do
      assert Scorer.score("movie a", "movie a") == 1.0
    end

    test "exact match with single-word candidate returns 1.0" do
      assert Scorer.score("solo", "solo") == 1.0
    end
  end

  describe "score/2 — prefix match" do
    test "prefix match scores at least 0.7" do
      score = Scorer.score("movi", "movie a")
      assert score >= 0.7
      assert score < 1.0
    end

    test "longer prefix scores closer to 1.0 than shorter prefix" do
      short = Scorer.score("m", "movie a")
      long = Scorer.score("movie", "movie a")

      assert short >= 0.7
      assert long >= 0.7
      assert long > short
    end

    test "prefix score is bounded by 0.9 ceiling on length difference" do
      # Even the closest non-exact prefix can never reach 1.0 (that's
      # reserved for full equality).
      assert Scorer.score("movie ", "movie a") < 1.0
    end
  end

  describe "score/2 — substring (non-prefix)" do
    test "substring in the middle scores in [0.4, 0.7]" do
      score = Scorer.score("movie", "the movie show")
      assert score >= 0.4
      assert score <= 0.7
    end

    test "longer substring relative to candidate scores higher than tiny substring" do
      tiny = Scorer.score("m", "the movie show")
      long = Scorer.score("movie", "the movie show")

      # Both clamped into [0.4, 0.7]; longer ratio scores at least as
      # high as shorter.
      assert long >= tiny
    end

    test "substring score is strictly below prefix score for the same query length" do
      # "ovie" — substring at index 1 of "movie a"; vs "movi" — prefix
      # of "movie a". Same length, same candidate; prefix must beat
      # substring.
      prefix_score = Scorer.score("movi", "movie a")
      substring_score = Scorer.score("ovie", "movie a")

      assert prefix_score > substring_score
    end
  end

  describe "score/2 — jaro fallback" do
    test "single-character typos against the same word return the jaro score" do
      # `mvoie` vs `movie` — single transposition; Jaro = 0.9333, above
      # the 0.92 threshold (see scorer moduledoc for the rationale).
      score = Scorer.score("mvoie", "movie")
      jaro = String.jaro_distance("mvoie", "movie")

      assert jaro >= 0.92
      assert score == jaro
    end

    test "unrelated strings return 0.0" do
      # Completely unrelated terms — Jaro near 0; well below threshold.
      assert Scorer.score("xyz", "movie a") == 0.0
    end

    test "near-miss titles that only share a common prefix do not match via jaro" do
      # `movie a` vs `movie b` — Jaro = 0.9047, below the 0.92 threshold
      # on purpose: an exact-match query for "Movie A" must not surface
      # "Movie B" as a fuzzy hit. This is the integration-level invariant
      # the Search projection relies on.
      jaro = String.jaro_distance("movie a", "movie b")

      assert jaro < 0.92
      assert Scorer.score("movie a", "movie b") == 0.0
    end
  end

  describe "score/2 — ranking invariants" do
    test "exact > prefix > substring for the same target string" do
      exact = Scorer.score("movie", "movie")
      prefix = Scorer.score("movi", "movie")
      substring = Scorer.score("ovi", "movie")

      assert exact > prefix
      assert prefix > substring
    end
  end
end
