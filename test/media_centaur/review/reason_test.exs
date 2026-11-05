defmodule MediaCentaur.Review.ReasonTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Review

  describe "reason/1" do
    test "no match is :no_results" do
      assert Review.reason(%{tmdb_id: nil, candidates: []}) == :no_results
    end

    test "a best guess shared by two or more candidates is :tied" do
      assert Review.reason(%{tmdb_id: 123, candidates: [%{"score" => 0.7}, %{"score" => 0.7}]}) == :tied
    end

    test "a best guess ahead of the rest is :low_confidence" do
      assert Review.reason(%{tmdb_id: 123, candidates: [%{"score" => 0.8}, %{"score" => 0.5}]}) ==
               :low_confidence
    end

    test "a single candidate, no candidates, or no candidate list is not a tie" do
      assert Review.reason(%{tmdb_id: 123, candidates: [%{"score" => 0.9}]}) == :low_confidence
      assert Review.reason(%{tmdb_id: 123, candidates: []}) == :low_confidence
      assert Review.reason(%{tmdb_id: 123}) == :low_confidence
    end

    # A match that contradicts what a grab of ours asked for waits for a
    # person whatever its score; the row names the title the grab wanted.
    test "a match contradicting a grab is :grab_conflict, whatever its score" do
      file = %{tmdb_id: 123, confidence: 1.05, candidates: [%{"score" => 1.05}], wanted_title: "Movie J"}
      assert Review.reason(file) == :grab_conflict
    end

    # An approved item stays in the queue until the library reports its
    # file linked; until then it is importing, whatever its match looked like.
    test "an approved file is :importing" do
      assert Review.reason(%{status: :approved, tmdb_id: 123, candidates: [], error_message: nil}) ==
               :importing
    end

    # A file the library did not link comes back with the reason.
    test "a file returned with a reason is :not_added" do
      file = %{
        status: :pending,
        tmdb_id: 123,
        candidates: [],
        error_message: "Adding it to the library failed."
      }

      assert Review.reason(file) == :not_added
    end
  end
end
