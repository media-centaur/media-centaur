defmodule MediaCentaur.Search.CourQueriesTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.CourQueries

  # Generic placeholder title only (house rule). A run is a
  # `CourSegmentation` run map; `index` 1 is the second broadcast run.

  defp run(index, first_ep, last_ep) do
    %{index: index, first_ep: first_ep, last_ep: last_ep, date_span: nil}
  end

  defp queries(title, run), do: Enum.map(CourQueries.build(title, run), &elem(&1, 0))

  describe "build/2 — multi-episode later run" do
    test "emits absolute range, ordinal season, then TMDB-numbered range, in that order" do
      assert queries("Sample Show", run(1, {1, 29}, {1, 38})) == [
               "Sample Show 29-38",
               "Sample Show 2nd Season",
               "Sample Show Season 2",
               "Sample Show S01E29-E38"
             ]
    end

    test "the ordinal tracks the run index — third run reads as 3rd" do
      queries = queries("Sample Show", run(2, {1, 39}, {1, 48}))
      assert "Sample Show 3rd Season" in queries
      assert "Sample Show Season 3" in queries
    end
  end

  describe "build/2 — single-episode later run" do
    test "emits a bare-number and dashed form instead of a range" do
      assert queries("Sample Show", run(1, {1, 29}, {1, 29})) == [
               "Sample Show - 29",
               "Sample Show 2nd Season",
               "Sample Show Season 2",
               "Sample Show S01E29"
             ]
    end
  end

  describe "build/2 — first run is not cour-shaped" do
    test "the first run (index 0) yields no cour queries" do
      assert CourQueries.build("Sample Show", run(0, {1, 1}, {1, 16})) == []
    end
  end
end
