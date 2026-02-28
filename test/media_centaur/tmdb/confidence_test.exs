defmodule MediaCentaur.TMDB.ConfidenceTest do
  use ExUnit.Case, async: true
  alias MediaCentaur.TMDB.Confidence

  test "exact title match scores near 1.0" do
    result = %{"title" => "The Shadowy Sentinel", "release_date" => "2008-07-18"}
    score = Confidence.score("The Shadowy Sentinel", 2008, result, "title", "release_date", true)
    assert score >= 0.95
  end

  test "year bonus raises score" do
    # Use a slightly different title so the base Jaro distance is < 1.0, leaving room for bonuses
    result = %{"title" => "Inception", "release_date" => "2010-07-16"}
    with_year = Confidence.score("Inception Film", 2010, result, "title", "release_date", false)
    without_year = Confidence.score("Inception Film", nil, result, "title", "release_date", false)
    assert with_year > without_year
  end

  test "position bonus raises score" do
    # Use a slightly different title so the base Jaro distance is < 1.0, leaving room for bonuses
    result = %{"title" => "Inception", "release_date" => "2010-07-16"}
    top = Confidence.score("Inception Film", 2010, result, "title", "release_date", true)
    not_top = Confidence.score("Inception Film", 2010, result, "title", "release_date", false)
    assert top > not_top
  end

  test "score is clamped to 1.0" do
    result = %{"title" => "Exact Match", "release_date" => "2020-01-01"}
    score = Confidence.score("Exact Match", 2020, result, "title", "release_date", true)
    assert score <= 1.0
  end

  test "completely different title scores low" do
    result = %{"title" => "Avengers: Endgame", "release_date" => "2019-04-26"}
    score = Confidence.score("Finding Nemo", nil, result, "title", "release_date", false)
    assert score < 0.6
  end

  test "handles special characters in titles" do
    result = %{"title" => "Schindler's List", "release_date" => "1993-12-15"}
    score = Confidence.score("Schindlers List", 1993, result, "title", "release_date", false)
    assert score >= 0.80
  end

  test "nil year does not crash" do
    result = %{"title" => "Sample Movie Eight", "release_date" => nil}
    assert is_float(Confidence.score("Sample Movie Eight", nil, result, "title", "release_date", false))
  end
end
