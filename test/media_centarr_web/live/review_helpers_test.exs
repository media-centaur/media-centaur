defmodule MediaCentarrWeb.ReviewHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.ReviewHelpers

  # --- review_reason/1 ---

  describe "review_reason/1" do
    test "returns :no_results when tmdb_id is nil" do
      file = %{tmdb_id: nil, candidates: []}
      assert ReviewHelpers.review_reason(file) == :no_results
    end

    test "returns :tied when candidates have equal scores" do
      file = %{
        tmdb_id: 123,
        candidates: [%{"score" => 0.7}, %{"score" => 0.7}]
      }

      assert ReviewHelpers.review_reason(file) == :tied
    end

    test "returns :low_confidence when tmdb_id present and not tied" do
      file = %{
        tmdb_id: 123,
        candidates: [%{"score" => 0.8}, %{"score" => 0.5}]
      }

      assert ReviewHelpers.review_reason(file) == :low_confidence
    end
  end

  # --- count_by_reason/1 ---

  describe "count_by_reason/1" do
    test "counts groups by reason category" do
      groups = [
        %{representative: %{tmdb_id: nil, candidates: []}},
        %{representative: %{tmdb_id: nil, candidates: []}},
        %{representative: %{tmdb_id: 1, candidates: [%{"score" => 0.5}, %{"score" => 0.5}]}},
        %{representative: %{tmdb_id: 1, candidates: [%{"score" => 0.8}, %{"score" => 0.3}]}}
      ]

      assert ReviewHelpers.count_by_reason(groups) == %{
               no_results: 2,
               tied: 1,
               low_confidence: 1
             }
    end

    test "returns zeros for empty list" do
      assert ReviewHelpers.count_by_reason([]) == %{no_results: 0, tied: 0, low_confidence: 0}
    end
  end

  # --- tied_candidates?/1 ---

  describe "tied_candidates?/1" do
    test "returns true when two or more candidates share the same score" do
      file = %{candidates: [%{"score" => 0.7}, %{"score" => 0.7}]}
      assert ReviewHelpers.tied_candidates?(file)
    end

    test "returns false when candidates have different scores" do
      file = %{candidates: [%{"score" => 0.8}, %{"score" => 0.5}]}
      refute ReviewHelpers.tied_candidates?(file)
    end

    test "returns false for a single candidate" do
      file = %{candidates: [%{"score" => 0.9}]}
      refute ReviewHelpers.tied_candidates?(file)
    end

    test "returns false for empty candidates" do
      file = %{candidates: []}
      refute ReviewHelpers.tied_candidates?(file)
    end

    test "returns false when no candidates key" do
      refute ReviewHelpers.tied_candidates?(%{})
    end
  end

  # --- sort_candidates_by_year/1 ---

  describe "sort_candidates_by_year/1" do
    test "sorts by year ascending" do
      candidates = [
        %{"title" => "C", "year" => "2020"},
        %{"title" => "A", "year" => "2010"},
        %{"title" => "B", "year" => "2015"}
      ]

      result = ReviewHelpers.sort_candidates_by_year(candidates)
      years = Enum.map(result, & &1["year"])

      assert years == ["2010", "2015", "2020"]
    end

    test "puts nil years last" do
      candidates = [
        %{"title" => "A", "year" => nil},
        %{"title" => "B", "year" => "2010"}
      ]

      result = ReviewHelpers.sort_candidates_by_year(candidates)
      assert hd(result)["title"] == "B"
    end

    test "handles integer years" do
      candidates = [
        %{"title" => "B", "year" => 2020},
        %{"title" => "A", "year" => 2010}
      ]

      result = ReviewHelpers.sort_candidates_by_year(candidates)
      assert hd(result)["title"] == "A"
    end
  end

  # --- confidence display ---

  describe "confidence_text_class/1" do
    test "returns success for high scores" do
      assert ReviewHelpers.confidence_text_class(0.9) == "text-success"
      assert ReviewHelpers.confidence_text_class(0.8) == "text-success"
    end

    test "returns warning for medium scores" do
      assert ReviewHelpers.confidence_text_class(0.6) == "text-warning"
      assert ReviewHelpers.confidence_text_class(0.5) == "text-warning"
    end

    test "returns error for low scores" do
      assert ReviewHelpers.confidence_text_class(0.3) == "text-error"
    end
  end

  describe "confidence_bar_class/1" do
    test "returns success for high scores" do
      assert ReviewHelpers.confidence_bar_class(0.85) == "bg-success"
    end

    test "returns warning for medium scores" do
      assert ReviewHelpers.confidence_bar_class(0.6) == "bg-warning"
    end

    test "returns error for low scores" do
      assert ReviewHelpers.confidence_bar_class(0.2) == "bg-error"
    end
  end

  # --- reason display ---

  describe "reason_label/1" do
    test "returns labels for each reason" do
      assert ReviewHelpers.reason_label(:no_results) == "No TMDB results"
      assert ReviewHelpers.reason_label(:low_confidence) == "Low confidence"
      assert ReviewHelpers.reason_label(:tied) == "Tied match"
    end
  end

  describe "reason_text_class/1" do
    test "returns text classes for each reason" do
      assert ReviewHelpers.reason_text_class(:no_results) == "text-error"
      assert ReviewHelpers.reason_text_class(:low_confidence) == "text-warning"
      assert ReviewHelpers.reason_text_class(:tied) == "text-info"
    end
  end

  # --- format_type/1 ---

  describe "format_type/1" do
    test "formats known string types" do
      assert ReviewHelpers.format_type("movie") == "Movie"
      assert ReviewHelpers.format_type("tv") == "TV"
      assert ReviewHelpers.format_type("extra") == "Extra"
      assert ReviewHelpers.format_type("unknown") == "Unknown"
    end

    test "returns Unknown for nil" do
      assert ReviewHelpers.format_type(nil) == "Unknown"
    end

    test "capitalizes atom types" do
      assert ReviewHelpers.format_type(:documentary) == "Documentary"
    end
  end

  # --- sort_groups/1 ---

  describe "sort_groups/1" do
    test "sorts no-result groups before matched groups" do
      no_result = %{representative: %{tmdb_id: nil, confidence: nil}}
      matched = %{representative: %{tmdb_id: 123, confidence: 0.5}}

      result = ReviewHelpers.sort_groups([matched, no_result])
      assert hd(result).representative.tmdb_id == nil
    end

    test "sorts lower confidence before higher within matched" do
      low = %{representative: %{tmdb_id: 1, confidence: 0.3}}
      high = %{representative: %{tmdb_id: 2, confidence: 0.8}}

      result = ReviewHelpers.sort_groups([high, low])
      assert hd(result).representative.confidence == 0.3
    end
  end
end
